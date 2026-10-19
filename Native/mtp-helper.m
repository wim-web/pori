#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>

// Kalam's exported ABI accepts the function address cast to callback*, not &callback.
typedef void (*Callback)(char *);
typedef void (*Simple)(Callback *);
typedef void (*Input)(char *, Callback *);
typedef void (*Transfer)(char *, Callback *, Callback *, Callback *);
static FILE *wire;
static long requestID;
static pthread_mutex_t outputLock = PTHREAD_MUTEX_INITIALIZER;

static void emit(NSString *event, NSDictionary *result) {
    @autoreleasepool {
        NSDictionary *message = @{ @"id": @(requestID), @"event": event, @"result": result };
        NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
        pthread_mutex_lock(&outputLock);
        fwrite(data.bytes, 1, data.length, wire);
        fputc('\n', wire);
        fflush(wire);
        pthread_mutex_unlock(&outputLock);
    }
}
static void callback(char *json, NSString *event) {
    @autoreleasepool {
        NSData *data = json ? [NSData dataWithBytes:json length:strlen(json)] : nil;
        NSDictionary *result = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        emit(event, result ?: @{ @"error": @"Invalid engine response", @"errorType": @"ProtocolError" });
        free(json); // Kalam allocates callback strings with C.CString.
    }
}
static void done(char *json) { callback(json, @"done"); }
static void progress(char *json) { callback(json, @"progress"); }
static void preprocess(char *json) { callback(json, @"preprocess"); }
static void ignore(char *json) { free(json); }
static BOOL validItemPath(id path) {
    return [path isKindOfClass:NSString.class] && [path hasPrefix:@"/"] && ![path isEqual:@"/"] && [path isEqual:[path stringByStandardizingPath]];
}
static BOOL validName(id name) {
    if (![name isKindOfClass:NSString.class]) return NO;
    return [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0
        && ![name isEqual:@"."] && ![name isEqual:@".."]
        && [name rangeOfString:@"/"].location == NSNotFound && [name rangeOfString:@"\\"].location == NSNotFound
        && [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        wire = fdopen(dup(STDOUT_FILENO), "w");
        // Engine diagnostics must never corrupt the JSON transport.
        dup2(STDERR_FILENO, STDOUT_FILENO);
        if (argc != 2) return 64;
        void *lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
        if (!lib) { fprintf(stderr, "%s\n", dlerror()); return 70; }
        Simple init = dlsym(lib, "Initialize"), storages = dlsym(lib, "FetchStorages"), dispose = dlsym(lib, "Dispose");
        Input walk = dlsym(lib, "Walk"), exists = dlsym(lib, "FileExists"), deleteFile = dlsym(lib, "DeleteFile");
        Input mkdir = dlsym(lib, "MakeDirectory"), rename = dlsym(lib, "RenameFile");
        Input moveFiles = dlsym(lib, "MoveFiles");
        Transfer upload = dlsym(lib, "UploadFiles"), download = dlsym(lib, "DownloadFiles");
        if (!init || !storages || !dispose || !walk || !exists || !deleteFile || !mkdir || !rename || !moveFiles || !upload || !download) return 70;
        char *line = NULL; size_t capacity = 0; ssize_t length;
        while ((length = getline(&line, &capacity, stdin)) > 0) {
            @autoreleasepool {
                NSData *data = [NSData dataWithBytes:line length:(NSUInteger)length];
                NSDictionary *request = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (![request isKindOfClass:NSDictionary.class]) continue;
                requestID = [request[@"id"] longValue];
                NSString *command = request[@"command"];
                NSData *payload = [NSJSONSerialization dataWithJSONObject:request[@"payload"] ?: @{} options:0 error:nil];
                char *input = strndup(payload.bytes, payload.length);
                if ([command isEqual:@"connect"]) init((Callback *)done);
                else if ([command isEqual:@"storages"]) storages((Callback *)done);
                else if ([command isEqual:@"list"]) walk(input, (Callback *)done);
                else if ([command isEqual:@"exists"]) exists(input, (Callback *)done);
                else if ([command isEqual:@"move"]) moveFiles(input, (Callback *)done);
                else if ([command isEqual:@"mkdir"] || [command isEqual:@"rename"]) {
                    NSDictionary *arguments = request[@"payload"];
                    id fullPath = arguments[@"fullPath"];
                    BOOL valid = [arguments[@"storageId"] unsignedLongLongValue] > 0 && validItemPath(fullPath);
                    if ([command isEqual:@"mkdir"]) {
                        valid = valid && validName([fullPath lastPathComponent]);
                        if (valid) mkdir(input, (Callback *)done);
                    } else {
                        valid = valid && validName(arguments[@"newFileName"]);
                        if (valid) rename(input, (Callback *)done);
                    }
                    if (!valid) emit(@"done", @{ @"error": @"Invalid folder or filename", @"errorType": @"ProtocolError" });
                }
                else if ([command isEqual:@"delete"]) {
                    NSDictionary *arguments = request[@"payload"];
                    NSArray *paths = arguments[@"Files"];
                    BOOL valid = [paths isKindOfClass:NSArray.class] && paths.count > 0 && [arguments[@"storageId"] unsignedLongLongValue] > 0;
                    if (valid) {
                        for (id path in paths) {
                            if (![path isKindOfClass:NSString.class] || ![path hasPrefix:@"/"] || [path isEqual:@"/"] || ![path isEqual:[path stringByStandardizingPath]]) { valid = NO; break; }
                        }
                    }
                    if (valid) deleteFile(input, (Callback *)done);
                    else emit(@"done", @{ @"error": @"Invalid deletion target", @"errorType": @"ProtocolError" });
                }
                else if ([command isEqual:@"upload"]) upload(input, (Callback *)preprocess, (Callback *)progress, (Callback *)done);
                else if ([command isEqual:@"download"]) download(input, (Callback *)preprocess, (Callback *)progress, (Callback *)done);
                else if ([command isEqual:@"disconnect"]) dispose((Callback *)done);
                else emit(@"done", @{ @"error": @"Unknown command", @"errorType": @"ProtocolError" });
                free(input);
            }
        }
        free(line);
        dispose((Callback *)ignore);
        return 0;
    }
}
