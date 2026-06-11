cmake_minimum_required(VERSION 3.22)
project("soulo_whisper")

# Whisper.cpp will be downloaded separately into android/app/src/main/cpp/whisper.cpp
# Users should run: git clone https://github.com/ggerganov/whisper.cpp android/app/src/main/cpp/whisper.cpp

set(WHISPER_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/whisper.cpp")

if(EXISTS "${WHISPER_SRC_DIR}/ggml.c")
    add_library(whisper_core STATIC
        "${WHISPER_SRC_DIR}/ggml.c"
        "${WHISPER_SRC_DIR}/whisper.cpp"
    )

    target_include_directories(whisper_core PUBLIC "${WHISPER_SRC_DIR}")
    target_compile_options(whisper_core PRIVATE -O3 -ffast-math -pthread)
    target_link_libraries(whisper_core PUBLIC log m c++)

    add_library(soulo_whisper SHARED whisper_jni.cpp)
    target_include_directories(soulo_whisper PUBLIC "${WHISPER_SRC_DIR}")
    target_link_libraries(soulo_whisper whisper_core log)
else()
    # Stub: whisper.cpp not checked out — print warning
    message(WARNING "whisper.cpp not found at ${WHISPER_SRC_DIR}. Run: git submodule update --init or clone manually.")
    add_library(soulo_whisper SHARED whisper_jni.cpp)
    target_link_libraries(soulo_whisper log)
endif()

# ONNX Runtime — downloaded separately
# Add onnxruntime Android AAR as a Gradle dependency instead
