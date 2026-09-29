#include <napi/native_api.h>
#include <node_api.h>

#include <onnxruntime_cxx_api.h>

#include <array>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace {

Ort::Env g_env{ORT_LOGGING_LEVEL_FATAL, "mychu-captcha-ocr"};
std::mutex g_mutex;
std::unique_ptr<Ort::Session> g_session;
std::string g_input_name;
std::string g_output_name;

napi_value ThrowError(napi_env env, const char* message) {
  napi_throw_error(env, nullptr, message);
  return nullptr;
}

bool ReadUint8Array(napi_env env, napi_value value, const uint8_t** data,
                    size_t* length) {
  napi_typedarray_type type;
  void* raw_data = nullptr;
  napi_value array_buffer;
  size_t byte_offset = 0;
  if (napi_get_typedarray_info(env, value, &type, length, &raw_data,
                               &array_buffer, &byte_offset) != napi_ok ||
      type != napi_uint8_array || raw_data == nullptr) {
    return false;
  }
  *data = static_cast<const uint8_t*>(raw_data);
  return true;
}

bool ReadFloat32Array(napi_env env, napi_value value, const float** data,
                      size_t* length) {
  napi_typedarray_type type;
  size_t napi_length = 0;
  void* raw_data = nullptr;
  napi_value array_buffer;
  size_t byte_offset = 0;
  if (napi_get_typedarray_info(env, value, &type, &napi_length, &raw_data,
                               &array_buffer, &byte_offset) != napi_ok ||
      type != napi_float32_array || raw_data == nullptr) {
    return false;
  }

  // HarmonyOS SDK 26 reports bytes instead of elements for Float32Array here.
  napi_value js_length;
  uint32_t element_count = 0;
  if (napi_get_named_property(env, value, "length", &js_length) != napi_ok ||
      napi_get_value_uint32(env, js_length, &element_count) != napi_ok ||
      (napi_length != static_cast<size_t>(element_count) &&
       napi_length != static_cast<size_t>(element_count) * sizeof(float))) {
    return false;
  }
  *length = static_cast<size_t>(element_count);
  *data = static_cast<const float*>(raw_data);
  return true;
}

napi_value Initialize(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok ||
      argc != 1) {
    return ThrowError(env, "Invalid ONNX model data.");
  }

  const uint8_t* model_data = nullptr;
  size_t model_size = 0;
  if (!ReadUint8Array(env, args[0], &model_data, &model_size) ||
      model_size == 0) {
    return ThrowError(env, "Invalid ONNX model data.");
  }

  try {
    std::lock_guard<std::mutex> lock(g_mutex);
    Ort::SessionOptions options;
    options.SetIntraOpNumThreads(2);
    options.SetInterOpNumThreads(1);
    options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    auto session = std::make_unique<Ort::Session>(
        g_env, model_data, model_size, options);
    if (session->GetInputCount() != 1 || session->GetOutputCount() != 1) {
      return ThrowError(env, "Unexpected captcha model input/output count.");
    }

    Ort::AllocatorWithDefaultOptions allocator;
    auto input_name = session->GetInputNameAllocated(0, allocator);
    auto output_name = session->GetOutputNameAllocated(0, allocator);
    if (!input_name || !output_name) {
      return ThrowError(env, "Captcha model input/output name is unavailable.");
    }
    const auto output_type =
        session->GetOutputTypeInfo(0).GetTensorTypeAndShapeInfo();
    if (output_type.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
      return ThrowError(env, "Captcha model output must use float32.");
    }

    g_input_name = input_name.get();
    g_output_name = output_name.get();
    g_session = std::move(session);
    napi_value result;
    if (napi_get_undefined(env, &result) != napi_ok) return nullptr;
    return result;
  } catch (...) {
    return ThrowError(env, "Captcha ONNX model initialization failed.");
  }
}

napi_value Run(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok ||
      argc != 3) {
    return ThrowError(env, "Invalid captcha tensor.");
  }

  const float* input_data = nullptr;
  size_t input_count = 0;
  int64_t height = 0;
  int64_t width = 0;
  if (!ReadFloat32Array(env, args[0], &input_data, &input_count) ||
      napi_get_value_int64(env, args[1], &height) != napi_ok ||
      napi_get_value_int64(env, args[2], &width) != napi_ok || height <= 0 ||
      width <= 0 ||
      static_cast<uint64_t>(height) * static_cast<uint64_t>(width) !=
          input_count) {
    return ThrowError(env, "Invalid captcha tensor dimensions.");
  }

  try {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_session) {
      return ThrowError(env, "Captcha ONNX session is not initialized.");
    }

    const std::array<int64_t, 4> input_shape = {1, 1, height, width};
    auto memory_info =
        Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    auto input = Ort::Value::CreateTensor<float>(
        memory_info, const_cast<float*>(input_data), input_count,
        input_shape.data(), input_shape.size());
    const char* input_names[] = {g_input_name.c_str()};
    const char* output_names[] = {g_output_name.c_str()};
    auto outputs = g_session->Run(Ort::RunOptions{nullptr}, input_names,
                                  &input, 1, output_names, 1);
    if (outputs.size() != 1 || !outputs[0].IsTensor()) {
      return ThrowError(env, "Captcha ONNX output is unavailable.");
    }

    auto output_info = outputs[0].GetTensorTypeAndShapeInfo();
    if (output_info.GetElementType() != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
      return ThrowError(env, "Captcha ONNX output must use float32.");
    }
    const auto output_shape = output_info.GetShape();
    const size_t output_count = output_info.GetElementCount();
    const float* output_data = outputs[0].GetTensorData<float>();
    if (output_count == 0 || output_data == nullptr || output_shape.empty() ||
        output_shape.size() > 4) {
      return ThrowError(env, "Invalid captcha ONNX output dimensions.");
    }

    napi_value output_buffer;
    void* output_buffer_data = nullptr;
    if (napi_create_arraybuffer(env, output_count * sizeof(float),
                                &output_buffer_data,
                                &output_buffer) != napi_ok ||
        output_buffer_data == nullptr) {
      return ThrowError(env, "Captcha ONNX output allocation failed.");
    }
    std::memcpy(output_buffer_data, output_data, output_count * sizeof(float));

    napi_value output_values;
    if (napi_create_typedarray(env, napi_float32_array, output_count,
                               output_buffer, 0, &output_values) != napi_ok) {
      return ThrowError(env, "Captcha ONNX output encoding failed.");
    }

    napi_value shape_values;
    if (napi_create_array_with_length(env, output_shape.size(),
                                      &shape_values) != napi_ok) {
      return ThrowError(env, "Captcha ONNX shape encoding failed.");
    }
    for (size_t index = 0; index < output_shape.size(); ++index) {
      napi_value dimension;
      if (napi_create_int64(env, output_shape[index], &dimension) != napi_ok ||
          napi_set_element(env, shape_values, index, dimension) != napi_ok) {
        return ThrowError(env, "Captcha ONNX shape encoding failed.");
      }
    }

    napi_value result;
    if (napi_create_object(env, &result) != napi_ok ||
        napi_set_named_property(env, result, "data", output_values) != napi_ok ||
        napi_set_named_property(env, result, "shape", shape_values) != napi_ok) {
      return ThrowError(env, "Captcha ONNX result encoding failed.");
    }
    return result;
  } catch (...) {
    return ThrowError(env, "Captcha ONNX inference failed.");
  }
}

napi_value Close(napi_env env, napi_callback_info info) {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_session.reset();
  g_input_name.clear();
  g_output_name.clear();
  napi_value result;
  if (napi_get_undefined(env, &result) != napi_ok) return nullptr;
  return result;
}

}  // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
      {"initialize", nullptr, Initialize, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"run", nullptr, Run, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"close", nullptr, Close, nullptr, nullptr, nullptr, napi_default,
       nullptr},
  };
  if (napi_define_properties(env, exports, 3, properties) != napi_ok) {
    napi_throw_error(env, "EINVAL", "Failed to export captcha OCR methods.");
    return nullptr;
  }
  return exports;
}
EXTERN_C_END

static napi_module captchaOcrModule = {
    NAPI_MODULE_VERSION,
    0,
    nullptr,
    Init,
    "mychu_captcha_ocr",
    nullptr,
    {0},
};

extern "C" __attribute__((constructor)) void RegisterCaptchaOcrModule() {
  napi_module_register(&captchaOcrModule);
}
