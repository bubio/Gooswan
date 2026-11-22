// The desktop app exchanges bounded frames over stdin/stdout. Only this
// process reads the device token and connects to the Swan Revival service.
package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/coder/websocket"
)

const service = "https://wg.swanrevival.com"
const maxFrame = 8192

var errLinkRequired = errors.New("Link your Swan Revival account first")

const roomAlphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"

type frame struct {
	kind byte
	data []byte
}

func readFrame(r io.Reader) (frame, error) {
	var header [3]byte
	if _, err := io.ReadFull(r, header[:]); err != nil {
		return frame{}, err
	}
	n := binary.LittleEndian.Uint16(header[1:])
	if n > maxFrame {
		return frame{}, errors.New("oversized desktop frame")
	}
	f := frame{header[0], make([]byte, n)}
	_, err := io.ReadFull(r, f.data)
	return f, err
}

func writeFrame(w io.Writer, kind byte, data []byte) error {
	if len(data) > maxFrame {
		return errors.New("oversized room frame")
	}
	packet := make([]byte, 3+len(data))
	packet[0] = kind
	binary.LittleEndian.PutUint16(packet[1:], uint16(len(data)))
	copy(packet[3:], data)
	_, err := w.Write(packet)
	return err
}

func roomCode(input string) string {
	code := strings.ToUpper(strings.NewReplacer(" ", "", "-", "").Replace(strings.TrimSpace(input)))
	if len(code) != 6 || strings.ContainsFunc(code, func(c rune) bool { return !strings.ContainsRune(roomAlphabet, c) }) {
		return ""
	}
	return code
}

func pair(ctx context.Context, out io.Writer, endpoint, path, code string) error {
	body, err := json.Marshal(map[string]string{"code": strings.TrimSpace(code), "name": "Gooswan"})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	client := http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	resp, err := client.Do(req)
	if err != nil {
		return errors.New("Could not reach Swan Revival")
	}
	defer resp.Body.Close()
	var device struct{ Token string }
	if resp.StatusCode < 200 || resp.StatusCode >= 300 || json.NewDecoder(io.LimitReader(resp.Body, maxFrame)).Decode(&device) != nil || device.Token == "" {
		return errors.New("Swan Revival rejected the device code")
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".link-token-*")
	if err != nil {
		return errors.New("Could not save the Swan Revival device token")
	}
	defer os.Remove(file.Name())
	_, err = io.WriteString(file, device.Token)
	closeErr := file.Close()
	if err != nil || closeErr != nil || os.Rename(file.Name(), path) != nil {
		return errors.New("Could not save the Swan Revival device token")
	}
	return writeFrame(out, 'A', nil)
}

type roomMessage struct {
	Seat    json.RawMessage `json:"seat"`
	Peer    json.RawMessage `json:"peer"`
	Start   json.RawMessage `json:"start"`
	Left    json.RawMessage `json:"left"`
	Error   string          `json:"error"`
	Baud    int             `json:"baud"`
	Overrun string          `json:"overrun"`
}

func roomError(code string) error {
	if code == "sign-in" {
		return errLinkRequired
	}
	messages := map[string]string{
		"no-room": "Room not found", "full": "Room is full",
		"name": "Set a player name on Swan Revival", "kicked": "The host removed you from the room",
		"closed": "The host closed the room", "limit": "Swan Revival room limit reached", "version": "Unsupported Swan Revival protocol version",
	}
	if msg := messages[code]; msg != "" {
		return errors.New(msg)
	}
	return errors.New("Swan Revival rejected the connection")
}

func roomDownload(ctx context.Context, ws *websocket.Conn, out io.Writer) error {
	var flags byte
	seated, started := false, false
	for {
		kind, data, err := ws.Read(ctx)
		if err != nil {
			return errors.New("Swan Revival room disconnected")
		}
		if kind == websocket.MessageBinary {
			if !started || len(data)%6 != 0 {
				return errors.New("Invalid Swan Revival cable data")
			}
			err = writeFrame(out, 'D', data)
		} else {
			var msg roomMessage
			if json.Unmarshal(data, &msg) != nil {
				return errors.New("Invalid Swan Revival room message")
			}
			switch {
			case msg.Error != "":
				return roomError(msg.Error)
			case msg.Left != nil:
				return errors.New("The other player left the room")
			case msg.Seat != nil && !seated:
				seated = true
				if msg.Overrun == "new" {
					flags |= 1
				}
				if msg.Baud == 38400 {
					flags |= 2
				}
				err = writeFrame(out, 'J', nil)
			case msg.Peer != nil && seated && !started:
				err = writeFrame(out, 'P', []byte{boolByte(!bytes.Equal(msg.Peer, []byte("null")))})
			case msg.Start != nil && seated && !started:
				started = true
				err = writeFrame(out, 'S', []byte{flags})
			}
		}
		if err != nil {
			return err
		}
	}
}

func boolByte(b bool) byte {
	if b {
		return 1
	}
	return 0
}

func roomUpload(ctx context.Context, ws *websocket.Conn, input <-chan frame) error {
	ping := time.NewTicker(2 * time.Second)
	defer ping.Stop()
	for {
		kind := websocket.MessageText
		var data []byte
		select {
		case <-ctx.Done():
			return ctx.Err()
		case t := <-ping.C:
			data = fmt.Appendf(nil, `{"ping":%d}`, t.UnixMilli())
		case f := <-input:
			switch {
			case f.kind == 'R' && len(f.data) == 0:
				data = []byte(`{"ready":true}`)
			case f.kind == 'D' && len(f.data)%6 == 0:
				kind, data = websocket.MessageBinary, f.data
			default:
				return errors.New("Invalid desktop cable data")
			}
		}
		writeCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		err := ws.Write(writeCtx, kind, data)
		cancel()
		if err != nil {
			return errors.New("Could not send to the Swan Revival room")
		}
	}
}

func join(ctx context.Context, in io.Reader, out io.Writer, url, token string) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	dialCtx, stopDial := context.WithTimeout(ctx, 10*time.Second)
	client := http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	ws, _, err := websocket.Dial(dialCtx, url, &websocket.DialOptions{HTTPClient: &client})
	stopDial()
	if err != nil {
		return errors.New("Could not open the Swan Revival room")
	}
	defer ws.CloseNow()
	ws.SetReadLimit(maxFrame)
	hello, err := json.Marshal(struct {
		Version int    `json:"v"`
		Token   string `json:"token"`
	}{1, token})
	if err != nil {
		return err
	}
	helloCtx, stopHello := context.WithTimeout(ctx, 5*time.Second)
	err = ws.Write(helloCtx, websocket.MessageText, hello)
	stopHello()
	if err != nil {
		return errors.New("Could not join the Swan Revival room")
	}

	input := make(chan frame, 16)
	go func() {
		for {
			f, err := readFrame(in)
			if err != nil {
				cancel()
				return
			}
			select {
			case input <- f:
			case <-ctx.Done():
				return
			}
		}
	}()
	result := make(chan error, 2)
	go func() { result <- roomDownload(ctx, ws, out) }()
	go func() { result <- roomUpload(ctx, ws, input) }()
	err = <-result
	cancel()
	<-result // no concurrent writes to the desktop pipe when reporting an error
	return err
}

func run(in io.Reader, out io.Writer, tokenFile string) error {
	first, err := readFrame(in)
	if err != nil {
		return err
	}
	ctx := context.Background()
	if first.kind == 'A' {
		ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
		defer cancel()
		return pair(ctx, out, service+"/link", tokenFile, string(first.data))
	}
	code := roomCode(string(first.data))
	if first.kind != 'J' || code == "" {
		return errors.New("Enter a six-character Swan Revival room code")
	}
	token, err := os.ReadFile(tokenFile)
	if err != nil || len(token) == 0 || len(token) > maxFrame {
		return errLinkRequired
	}
	return join(ctx, in, out, "wss://wg.swanrevival.com/room/"+code, strings.TrimSpace(string(token)))
}

func main() {
	if len(os.Args) != 2 {
		os.Exit(2)
	}
	if err := run(os.Stdin, os.Stdout, os.Args[1]); err != nil {
		if errors.Is(err, errLinkRequired) {
			_ = writeFrame(os.Stdout, 'L', nil)
		} else {
			_ = writeFrame(os.Stdout, 'E', []byte(err.Error()))
		}
		os.Exit(1)
	}
}
