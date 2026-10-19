package main

import (
	"fmt"
	"testing"
)

type fakeMoveDevice struct {
	objects map[string]moveEntry
	calls   []uint32
	failID  uint32
}

func (d *fakeMoveDevice) resolve(sid uint32, p string) (moveEntry, error) {
	if p == "/" {
		return moveEntry{ID: ^uint32(0), Folder: true}, nil
	}
	f, ok := d.objects[p]
	if !ok {
		return moveEntry{}, fmt.Errorf("missing")
	}
	return f, nil
}
func (d *fakeMoveDevice) children(sid uint32, p string) ([]moveEntry, error) {
	folder, err := d.resolve(sid, p)
	if err != nil {
		return nil, err
	}
	var entries []moveEntry
	for _, f := range d.objects {
		if f.Parent == folder.ID || (p == "/" && f.Parent == 0) {
			entries = append(entries, f)
		}
	}
	return entries, nil
}
func (d *fakeMoveDevice) info(id uint32) (moveEntry, error) {
	for _, f := range d.objects {
		if f.ID == id {
			return f, nil
		}
	}
	return moveEntry{}, fmt.Errorf("missing")
}
func (d *fakeMoveDevice) move(id, sid, parent uint32) error {
	d.calls = append(d.calls, id)
	if id == d.failID {
		return fmt.Errorf("device disconnected")
	}
	for p, f := range d.objects {
		if f.ID == id {
			f.Parent = parent
			d.objects[p] = f
			return nil
		}
	}
	return fmt.Errorf("missing")
}
func fixture() (*fakeMoveDevice, moveInput) {
	return &fakeMoveDevice{objects: map[string]moveEntry{
		"/From":         {ID: 10, Storage: 1, Name: "From", Folder: true},
		"/To":           {ID: 20, Storage: 1, Name: "To", Folder: true},
		"/From/日本語.txt": {ID: 11, Parent: 10, Storage: 1, Name: "日本語.txt"},
		"/From/Folder":  {ID: 12, Parent: 10, Storage: 1, Name: "Folder", Folder: true},
	}}, moveInput{StorageID: 1, SourceParent: "/From", Destination: "/To", Sources: []moveItem{{Path: "/From/日本語.txt", ObjectID: 11}, {Path: "/From/Folder", ObjectID: 12}}}
}
func TestMoveSuccessAndRoot(t *testing.T) {
	for _, destination := range []string{"/To", "/"} {
		d, input := fixture()
		input.Destination = destination
		if err := executeMove(d, input); err != nil {
			t.Fatal(err)
		}
		expected := uint32(20)
		if destination == "/" {
			expected = 0
		}
		for _, id := range []uint32{11, 12} {
			f, _ := d.info(id)
			if f.Parent != expected {
				t.Fatal("wrong parent", f)
			}
		}
	}
}
func TestMovePreflightRejectsBeforeAnyMutation(t *testing.T) {
	tests := map[string]func(*fakeMoveDevice, *moveInput){
		"same folder": func(d *fakeMoveDevice, i *moveInput) { i.Destination = "/From" },
		"self":        func(d *fakeMoveDevice, i *moveInput) { i.Destination = "/From/Folder" },
		"descendant":  func(d *fakeMoveDevice, i *moveInput) { i.Destination = "/From/Folder/Nested" },
		"collision": func(d *fakeMoveDevice, i *moveInput) {
			d.objects["/To/日本語.txt"] = moveEntry{ID: 30, Parent: 20, Storage: 1, Name: "日本語.txt"}
		},
		"stale id":       func(d *fakeMoveDevice, i *moveInput) { i.Sources[0].ObjectID = 99 },
		"duplicate":      func(d *fakeMoveDevice, i *moveInput) { i.Sources[1] = i.Sources[0] },
		"wrong storage":  func(d *fakeMoveDevice, i *moveInput) { i.StorageID = 2 },
		"outside parent": func(d *fakeMoveDevice, i *moveInput) { i.Sources[0].Path = "/To/x" },
		"empty":          func(d *fakeMoveDevice, i *moveInput) { i.Sources = nil },
		"unclean path":   func(d *fakeMoveDevice, i *moveInput) { i.Destination = "/To/../From" },
	}
	for name, modify := range tests {
		t.Run(name, func(t *testing.T) {
			d, i := fixture()
			modify(d, &i)
			if executeMove(d, i) == nil {
				t.Fatal("accepted invalid request")
			}
			if len(d.calls) != 0 {
				t.Fatal("mutated during failed preflight")
			}
		})
	}
}
func TestPartialFailureDoesNotRetryOrDelete(t *testing.T) {
	d, i := fixture()
	d.failID = 12
	if executeMove(d, i) == nil {
		t.Fatal("expected failure")
	}
	if len(d.calls) != 2 || d.calls[0] != 11 || d.calls[1] != 12 {
		t.Fatal("unexpected retry")
	}
	a, _ := d.info(11)
	b, _ := d.info(12)
	if a.Parent != 20 || b.Parent != 10 {
		t.Fatal("unexpected partial move state")
	}
}
