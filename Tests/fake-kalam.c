#include <stdlib.h>
#include <string.h>
typedef void (*cb)(char *);
static void emit(cb *callback, const char *json) { ((cb)callback)(strdup(json)); }
void Initialize(cb *c) { emit(c, "{\"error\":\"\",\"data\":{\"mtpDeviceInfo\":{\"Model\":\"Test device\"}}}"); }
void FetchStorages(cb *c) { emit(c, "{\"error\":\"\",\"data\":[{\"Sid\":65537,\"Info\":{\"StorageDescription\":\"Internal\",\"FreeSpaceInBytes\":9000000000}}]}"); }
void Dispose(cb *c) { emit(c, "{\"error\":\"\",\"data\":true}"); }
void Walk(char *input, cb *c) { emit(c, "{\"error\":\"\",\"data\":[{\"name\":\"日本語.txt\",\"path\":\"/日本語.txt\",\"size\":5000000000,\"isFolder\":false}]}"); }
void FileExists(char *input, cb *c) { emit(c, "{\"error\":\"\",\"data\":[{\"fullpath\":\"/日本語.txt\",\"exists\":true}]}"); }
void UploadFiles(char *input, cb *pre, cb *progress, cb *done) {
    emit(pre, "{\"error\":\"\",\"data\":{\"name\":\"日本語.txt\",\"size\":5000000000}}");
    emit(progress, "{\"error\":\"\",\"data\":{\"name\":\"日本語.txt\",\"bulkFileSize\":{\"total\":5000000000,\"sent\":2500000000}}}");
    emit(done, "{\"error\":\"\",\"data\":true}");
}
void DownloadFiles(char *input, cb *pre, cb *progress, cb *done) { emit(done, "{\"error\":\"Device unplugged\",\"errorType\":\"ErrorDeviceChanged\",\"data\":null}"); }
