/**
 * SummerTTS glog/gflags expect BSD u_int* types; OpenHarmony musl only has uint*_t.
 * Force-included for all SummerTTS translation units (see CMakeLists.txt).
 */
#ifndef SUMMERTTS_OHOS_COMPAT_H
#define SUMMERTTS_OHOS_COMPAT_H

#include <stdint.h>

#ifndef u_int8_t
typedef uint8_t u_int8_t;
#endif
#ifndef u_int16_t
typedef uint16_t u_int16_t;
#endif
#ifndef u_int32_t
typedef uint32_t u_int32_t;
#endif
#ifndef u_int64_t
typedef uint64_t u_int64_t;
#endif

#endif
