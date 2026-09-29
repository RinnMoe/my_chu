/*
* Copyright (c) 2025 Hunan OpenValley Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

#include "napi/native_api.h"
#include <uv.h>

static napi_value UvRunNowait(napi_env env, napi_callback_info info)
{
    uv_loop_s* loop = nullptr;
    napi_status status = napi_get_uv_event_loop(env, &loop);
    if (status != napi_ok || loop == nullptr) {
        napi_throw_error(env, "EINVAL", "Failed to get uv event loop");
        return nullptr;
    }
    uv_run(loop, UV_RUN_NOWAIT);
    return nullptr;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"uvRunNowait", nullptr, UvRunNowait, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_status status = napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    if (status != napi_ok) {
        napi_throw_error(env, "EINVAL", "Failed to define napi properties");
        return nullptr;
    }
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "inappwebview",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&demoModule);
}
