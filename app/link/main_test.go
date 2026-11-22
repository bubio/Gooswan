package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
)

func TestRoomCode(t *testing.T) {
	for typed, want := range map[string]string{
		" k7m-2qd ": "K7M2QD",
		"000000":    "", "K7M2QD/": "", "K7M2Q": "",
	} {
		if got := roomCode(typed); got != want {
			t.Errorf("roomCode(%q) = %q, want %q", typed, got, want)
		}
	}
}

func TestRoomHandshakeAndCableBytes(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	received := make(chan error, 1)
	sent := []byte{12, 0, 0, 0, 0xA5, 1}
	incoming := []byte{34, 0, 0, 0, 0x5A, 1}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		received <- serveRoom(ctx, w, r, sent, incoming)
	}))
	defer server.Close()

	input, commands := io.Pipe()
	events, output := io.Pipe()
	finished := make(chan error, 1)
	go func() {
		finished <- join(ctx, input, output, "ws"+strings.TrimPrefix(server.URL, "http")+"/room/K7M2QD", "fixture")
	}()
	defer input.Close()
	defer commands.Close()
	defer events.Close()
	defer output.Close()
	go func() { <-ctx.Done(); events.Close(); commands.Close() }()
	expect := func(kind byte, data []byte) {
		t.Helper()
		got, err := readFrame(events)
		if err != nil || got.kind != kind || !bytes.Equal(got.data, data) {
			t.Fatalf("got frame %q %v (%v), want %q %v", got.kind, got.data, err, kind, data)
		}
	}
	expect('J', nil)
	expect('P', []byte{1})
	if err := writeFrame(commands, 'R', nil); err != nil {
		t.Fatal(err)
	}
	expect('S', []byte{3})
	expect('D', incoming)
	if err := writeFrame(commands, 'D', sent); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-received:
		if err != nil {
			t.Fatal(err)
		}
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
	select {
	case err := <-finished:
		if err == nil || err.Error() != "The other player left the room" {
			t.Fatalf("room end: %v", err)
		}
	case <-ctx.Done():
		t.Fatal(ctx.Err())
	}
}

func serveRoom(ctx context.Context, w http.ResponseWriter, r *http.Request, sent, incoming []byte) error {
	if r.URL.Path != "/room/K7M2QD" {
		return fmt.Errorf("unexpected room URL %q", r.URL.Path)
	}
	ws, err := websocket.Accept(w, r, nil)
	if err != nil {
		return err
	}
	defer ws.CloseNow()
	kind, payload, err := ws.Read(ctx)
	var hello struct {
		Version int    `json:"v"`
		Token   string `json:"token"`
	}
	if err != nil || kind != websocket.MessageText || json.Unmarshal(payload, &hello) != nil || hello.Version != 1 || hello.Token != "fixture" {
		return fmt.Errorf("unexpected room hello: %s (%v)", payload, err)
	}
	for _, msg := range []string{`{"seat":0,"baud":38400,"overrun":"new"}`, `{"peer":{"handle":"other"}}`} {
		if err := ws.Write(ctx, websocket.MessageText, []byte(msg)); err != nil {
			return err
		}
	}
	kind, payload, err = ws.Read(ctx)
	if err != nil || kind != websocket.MessageText || string(payload) != `{"ready":true}` {
		return fmt.Errorf("unexpected Ready: %s (%v)", payload, err)
	}
	if err := ws.Write(ctx, websocket.MessageText, []byte(`{"start":true}`)); err != nil {
		return err
	}
	if err := ws.Write(ctx, websocket.MessageBinary, incoming); err != nil {
		return err
	}
	kind, payload, err = ws.Read(ctx)
	if err != nil || kind != websocket.MessageBinary || !bytes.Equal(payload, sent) {
		return fmt.Errorf("unexpected cable bytes: %v (%v)", payload, err)
	}
	return ws.Write(ctx, websocket.MessageText, []byte(`{"left":true}`))
}
