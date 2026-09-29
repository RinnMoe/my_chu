cmake_minimum_required(VERSION 3.4.1)
project(mychu_captcha_ocr)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

get_filename_component(MYCHU_REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../../.." REALPATH)
set(ONNXRUNTIME_ROOT "${MYCHU_REPO_ROOT}/third_party/onnxruntime_ohos")
set(ONNXRUNTIME_LIBRARY "${ONNXRUNTIME_ROOT}/lib/${OHOS_ARCH}/libonnxruntime.so")

if(NOT OHOS_ARCH STREQUAL "x86_64" AND NOT OHOS_ARCH STREQUAL "arm64-v8a")
  message(FATAL_ERROR "Unsupported Harmony ABI for ONNX Runtime: ${OHOS_ARCH}")
endif()

add_library(mychu_captcha_ocr SHARED mychu_captcha_ocr.cpp)
target_include_directories(mychu_captcha_ocr PRIVATE "${ONNXRUNTIME_ROOT}/include")
add_library(onnxruntime SHARED IMPORTED GLOBAL)
set_target_properties(onnxruntime PROPERTIES IMPORTED_LOCATION "${ONNXRUNTIME_LIBRARY}")
target_link_libraries(mychu_captcha_ocr PRIVATE onnxruntime libace_napi.z.so)


set_target_properties(mychu_captcha_ocr PROPERTIES
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "$ORIGIN"
)
