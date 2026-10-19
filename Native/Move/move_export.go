package main

/*
typedef void (* on_cb_result_t)(char*);
*/
import "C"
import (
	"encoding/json"
	"fmt"
	"github.com/ganeshrvel/go-mtpfs/mtp"
	"github.com/ganeshrvel/go-mtpx"
	"kalam/send_to_js"
)

type liveMoveDevice struct{ dev *mtp.Device }

func (d liveMoveDevice) resolve(sid uint32, p string) (moveEntry, error) {
	f, err := mtpx.GetObjectFromPath(d.dev, sid, p)
	if err != nil {
		return moveEntry{}, err
	}
	return moveEntry{ID: f.ObjectId, Parent: f.ParentId, Storage: f.Info.StorageID, Name: f.Name, Folder: f.IsDir}, nil
}
func (d liveMoveDevice) children(sid uint32, p string) ([]moveEntry, error) {
	parent, err := d.resolve(sid, p)
	if err != nil {
		return nil, err
	}
	handles := mtp.Uint32Array{}
	if err := d.dev.GetObjectHandles(sid, 0, parent.ID, &handles); err != nil {
		return nil, err
	}
	entries := []moveEntry{}
	for _, id := range handles.Values {
		entry, err := d.info(id)
		if err != nil {
			return nil, err
		}
		entries = append(entries, entry)
	}
	return entries, nil
}
func (d liveMoveDevice) info(id uint32) (moveEntry, error) {
	var info mtp.ObjectInfo
	if err := d.dev.GetObjectInfo(id, &info); err != nil {
		return moveEntry{}, err
	}
	return moveEntry{ID: id, Parent: info.ParentObject, Storage: info.StorageID, Name: info.Filename, Folder: info.ObjectFormat == 0x3001}, nil
}
func (d liveMoveDevice) move(id, sid, parent uint32) error {
	req := mtp.Container{Code: mtp.OC_MoveObject, Param: []uint32{id, sid, parent}}
	var response mtp.Container
	return d.dev.RunTransaction(&req, &response, nil, nil, 0, mtp.EmptyProgressFunc)
}

//export MoveFiles
func MoveFiles(raw *C.char, callback *C.on_cb_result_t) {
	result := (*send_to_js.SendCbResult)(callback)
	if err := verifyMtpSession(verifyMtpSessionMode{}); err != nil {
		send_to_js.SendError(result, err)
		return
	}
	supported := false
	for _, operation := range container.deviceInfo.OperationsSupported {
		if operation == mtp.OC_MoveObject {
			supported = true
		}
	}
	if !supported {
		send_to_js.SendError(result, fmt.Errorf("この端末はUSB経由のフォルダ間移動に対応していません。"))
		return
	}
	var input moveInput
	if err := json.Unmarshal([]byte(C.GoString(raw)), &input); err != nil {
		send_to_js.SendError(result, err)
		return
	}
	if err := executeMove(liveMoveDevice{container.dev}, input); err != nil {
		send_to_js.SendError(result, err)
		return
	}
	send_to_js.SendTransferFilesDone(result)
}
