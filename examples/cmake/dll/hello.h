#pragma once

#ifdef _WIN32
#define DLL_API __declspec(dllexport)
#else
#define DLL_API
#endif

#ifdef __cplusplus
extern "C" {
#endif
DLL_API const char *hello();
#ifdef __cplusplus
}
#endif
