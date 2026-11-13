#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        const char *path = argc > 1 ? argv[1] : "/System/Library/PrivateFrameworks/BatteryCenter.framework/BatteryCenter";
        void *handle = dlopen(path, RTLD_NOW);
        if (!handle) { fprintf(stderr, "%s\n", dlerror()); return 1; }
        unsigned int count = 0;
        Class *classes = objc_copyClassList(&count);
        for (unsigned int i = 0; i < count; i++) {
            const char *name = class_getName(classes[i]);
            if (strncmp(name, "BC", 2) != 0 && strncmp(name, "_BC", 3) != 0) continue;
            printf("CLASS %s\n", name);
            for (int meta = 0; meta < 2; meta++) {
                unsigned int n = 0;
                Method *methods = class_copyMethodList(meta ? object_getClass(classes[i]) : classes[i], &n);
                for (unsigned int j = 0; j < n; j++)
                    printf("  %c %s %s\n", meta ? '+' : '-', sel_getName(method_getName(methods[j])), method_getTypeEncoding(methods[j]));
                free(methods);
            }
        }
        free(classes);
        unsigned int protocolCount = 0;
        Protocol * __unsafe_unretained *protocols = objc_copyProtocolList(&protocolCount);
        for (unsigned int i = 0; i < protocolCount; i++) {
            const char *name = protocol_getName(protocols[i]);
            if (strncmp(name, "BC", 2)) continue;
            printf("PROTOCOL %s\n", name);
            for (int required = 0; required < 2; required++) {
                unsigned int n = 0;
                struct objc_method_description *methods = protocol_copyMethodDescriptionList(protocols[i], required, YES, &n);
                for (unsigned int j = 0; j < n; j++) printf("  %s %s\n", sel_getName(methods[j].name), methods[j].types);
                free(methods);
            }
        }
        free(protocols);
    }
}
