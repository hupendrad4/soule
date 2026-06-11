#include <jni.h>
#include <cstring>
#include <string>
#include <vector>
#include <android/log.h>

#define LOG_TAG "SouloWhisper"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Forward declare whisper API types so this compiles even without whisper.cpp
// When whisper.cpp is checked out, these are replaced by the real headers.
#ifndef GGML_API
#define GGML_API
#endif

struct whisper_context;
struct whisper_full_params;

extern "C" {
    struct whisper_context* whisper_init_from_file(const char* path);
    int whisper_full(struct whisper_context* ctx, whisper_full_params params, const float* samples, int n_samples);
    int whisper_full_n_segments(struct whisper_context* ctx);
    const char* whisper_full_get_segment_text(struct whisper_context* ctx, int i_segment);
    int whisper_full_get_segment_t0(struct whisper_context* ctx, int i_segment);
    int whisper_full_get_segment_t1(struct whisper_context* ctx, int i_segment);
    void whisper_free(struct whisper_context* ctx);
    int whisper_lang_id(const char* lang);
    int whisper_n_len_from_id(int id);
}

struct whisper_full_params {
    int strategy;
    int n_threads;
    int offset_ms;
    int audio_ctx;
    int progress_callback;
    int *progress_callback_user_data;
    int speed_up;
    int translate;
    int no_fallback;
    int print_special;
    int print_progress;
    int print_realtime;
    int print_timestamps;
    int language;
    int suppress_blank;
    int suppress_non_speech_tokens;
    float temperature;
    float temperature_inc;
    float entropy_thold;
    float logprob_thold;
    float no_speech_thold;
    int greedy_best_of;
    int beam_search_beam_size;
    float beam_search_patience;
    int new_segment_callback;
    int new_segment_callback_user_data;
    int encoder_begin_callback;
    int encoder_begin_callback_user_data;
    int logprob;
    int grammar_rules;
    int n_grammar_rules;
    int i_start_rule;
    int grammar_penalty;
};

// JNI wrapper
extern "C" JNIEXPORT jlong JNICALL
Java_com_soulo_app_utilities_WhisperWrapper_nativeInit(JNIEnv* env, jobject /*thiz*/,
                                                         jstring model_path) {
    const char* path = env->GetStringUTFChars(model_path, nullptr);
    if (!path) return 0;

    auto* ctx = whisper_init_from_file(path);
    env->ReleaseStringUTFChars(model_path, path);

    if (!ctx) {
        LOGE("Failed to init whisper from: %s", path);
        return 0;
    }
    LOGI("Whisper initialized from: %s", path);
    return reinterpret_cast<jlong>(ctx);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_soulo_app_utilities_WhisperWrapper_nativeTranscribe(JNIEnv* env, jobject /*thiz*/,
                                                               jlong ctx_ptr,
                                                               jshortArray pcm_data,
                                                               jint sample_rate,
                                                               jint n_threads) {
    if (!ctx_ptr) return env->NewStringUTF("");

    auto* ctx = reinterpret_cast<whisper_context*>(ctx_ptr);

    jshort* pcm = env->GetShortArrayElements(pcm_data, nullptr);
    jsize len = env->GetArrayLength(pcm_data);

    std::vector<float> pcmf32(len);
    for (int i = 0; i < len; i++) {
        pcmf32[i] = pcm[i] / 32768.0f;
    }

    env->ReleaseShortArrayElements(pcm_data, pcm, JNI_ABORT);

    whisper_full_params params = {};
    params.n_threads = n_threads;
    params.offset_ms = 0;
    params.speed_up = 0;
    params.translate = 0;
    params.print_special = 0;
    params.print_progress = 0;
    params.print_realtime = 0;
    params.print_timestamps = 0;
    params.language = whisper_lang_id("en");
    params.suppress_blank = 1;
    params.suppress_non_speech_tokens = 1;
    params.temperature = 0.0f;
    params.temperature_inc = 0.2f;
    params.entropy_thold = 2.4f;
    params.logprob_thold = -1.0f;
    params.no_speech_thold = 0.6f;
    params.greedy_best_of = 5;

    if (whisper_full(ctx, params, pcmf32.data(), pcmf32.size()) != 0) {
        LOGE("whisper_full failed");
        return env->NewStringUTF("");
    }

    std::string result;
    int n_segments = whisper_full_n_segments(ctx);
    for (int i = 0; i < n_segments; i++) {
        const char* text = whisper_full_get_segment_text(ctx, i);
        if (text) {
            if (!result.empty()) result += " ";
            result += text;
        }
    }

    return env->NewStringUTF(result.c_str());
}

extern "C" JNIEXPORT void JNICALL
Java_com_soulo_app_utilities_WhisperWrapper_nativeRelease(JNIEnv* env, jobject /*thiz*/,
                                                            jlong ctx_ptr) {
    if (!ctx_ptr) return;
    auto* ctx = reinterpret_cast<whisper_context*>(ctx_ptr);
    whisper_free(ctx);
    LOGI("Whisper released");
}
