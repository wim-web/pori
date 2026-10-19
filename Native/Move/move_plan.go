package main

import (
	"fmt"
	"path"
	"strings"
)

type moveItem struct {
	Path     string `json:"path"`
	ObjectID uint32 `json:"objectId"`
}
type moveInput struct {
	StorageID    uint32     `json:"storageId"`
	SourceParent string     `json:"sourceParent"`
	Destination  string     `json:"destination"`
	Sources      []moveItem `json:"sources"`
}
type moveEntry struct {
	ID, Parent, Storage uint32
	Name                string
	Folder              bool
}
type moveDevice interface {
	resolve(uint32, string) (moveEntry, error)
	children(uint32, string) ([]moveEntry, error)
	move(uint32, uint32, uint32) error
	info(uint32) (moveEntry, error)
}

func cleanMovePath(p string) bool {
	return strings.HasPrefix(p, "/") && path.Clean(p) == p && !strings.ContainsAny(p, "\\\x00")
}
func executeMove(d moveDevice, input moveInput) error {
	if input.StorageID == 0 || len(input.Sources) == 0 || !cleanMovePath(input.SourceParent) || !cleanMovePath(input.Destination) || input.SourceParent == input.Destination {
		return fmt.Errorf("現在のフォルダ以外の移動先を選んでください。")
	}
	seen := map[uint32]bool{}
	names := map[string]bool{}
	for _, source := range input.Sources {
		if !cleanMovePath(source.Path) || source.Path == "/" || path.Dir(source.Path) != input.SourceParent || source.ObjectID == 0 || source.ObjectID == ^uint32(0) || seen[source.ObjectID] {
			return fmt.Errorf("移動対象が不正です。一覧を更新して選び直してください。")
		}
		if input.Destination == source.Path || strings.HasPrefix(input.Destination, source.Path+"/") {
			return fmt.Errorf("フォルダ自身や、その中のフォルダには移動できません。")
		}
		key := strings.ToLower(path.Base(source.Path))
		if names[key] {
			return fmt.Errorf("同名の移動対象が複数あります。")
		}
		names[key] = true
		seen[source.ObjectID] = true
	}
	target, err := d.resolve(input.StorageID, input.Destination)
	if err != nil {
		return err
	}
	if !target.Folder || (input.Destination != "/" && target.Storage != input.StorageID) {
		return fmt.Errorf("移動先のフォルダを確認できません。")
	}
	children, err := d.children(input.StorageID, input.Destination)
	if err != nil {
		return err
	}
	for _, child := range children {
		if names[strings.ToLower(child.Name)] {
			return fmt.Errorf("移動先に同名の項目があります：%s", child.Name)
		}
	}
	for _, source := range input.Sources {
		current, err := d.resolve(input.StorageID, source.Path)
		if err != nil {
			return err
		}
		if current.ID != source.ObjectID || current.Storage != input.StorageID || current.Name != path.Base(source.Path) {
			return fmt.Errorf("移動対象が変わりました。一覧を更新してください。")
		}
	}
	parent := target.ID
	if input.Destination == "/" {
		parent = 0
	} // MoveObject uses zero for the storage root.
	for index, source := range input.Sources {
		if err := d.move(source.ObjectID, input.StorageID, parent); err != nil {
			return fmt.Errorf("完了を確認できたのは%d/%d項目です。一部が移動済みの可能性があります。再実行前に両方のフォルダを確認してください：%v", index, len(input.Sources), err)
		}
		current, err := d.info(source.ObjectID)
		correctParent := current.Parent == parent || (parent == 0 && current.Parent == ^uint32(0))
		if err != nil || !correctParent || current.Storage != input.StorageID || current.Name != path.Base(source.Path) {
			return fmt.Errorf("%d項目目の移動結果を確認できません。再実行前に両方のフォルダを確認してください。", index+1)
		}
	}
	return nil
}
