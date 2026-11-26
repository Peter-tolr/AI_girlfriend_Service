package com.mdkj.exception;

import lombok.extern.slf4j.Slf4j;
import org.springframework.ai.retry.NonTransientAiException;
import org.springframework.ai.retry.TransientAiException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 把 AI 调用失败转换成前端能看懂的结构化 JSON，而不是默认的 HTML 500 页面。
 *
 * <p>这里刻意不写 catch-all 的 {@code @ExceptionHandler(Exception.class)}，
 * 否则 Spring MVC 原本的 400 / 404 处理会被一并改成 500。</p>
 *
 * <p>提示里带上当前实际请求的地址和模型，换服务商以后能一眼看出是 Key 错了、
 * 地址填错了，还是模型名不对。</p>
 */
@Slf4j
@RestControllerAdvice
public class ApiExceptionHandler {

    private final String baseUrl;
    private final String chatPath;
    private final String model;

    public ApiExceptionHandler(@Value("${spring.ai.openai.base-url:}") String baseUrl,
                               @Value("${spring.ai.openai.chat.completions-path:/v1/chat/completions}") String chatPath,
                               @Value("${spring.ai.openai.chat.options.model:}") String model) {
        this.baseUrl = baseUrl;
        this.chatPath = chatPath;
        this.model = model;
    }

    @ExceptionHandler(ResponseStatusException.class)
    public ResponseEntity<Map<String, Object>> handleResponseStatus(ResponseStatusException e) {
        return build(e.getStatusCode().value(), e.getReason());
    }

    @ExceptionHandler({NonTransientAiException.class, TransientAiException.class, RestClientResponseException.class})
    public ResponseEntity<Map<String, Object>> handleAiException(Exception e) {
        String detail = rootMessage(e);
        int status = statusCode(e);
        String hint;
        if (status == 401 || status == 403 || isAuthFailure(detail)) {
            hint = "AI 接口鉴权失败：请检查 .env 里的 AI_API_KEY 是否有效，且与 AI_BASE_URL（" + baseUrl
                    + "）属于同一个服务商";
        } else if (status == 404) {
            hint = "AI 接口地址不存在（404）：当前请求 " + baseUrl + chatPath
                    + "，请检查 AI_BASE_URL / AI_CHAT_PATH 是否填对";
        } else if (status == 429) {
            hint = "AI 接口被限流（429）：请稍后再试，或换一个额度更充足的 Key";
        } else if (status == 400) {
            hint = "AI 接口拒绝了这次请求（400）：多半是模型名 " + model + " 不对，或该 Key 没有这个模型的权限";
        } else if (e instanceof TransientAiException) {
            hint = "AI 服务暂时不可用（超时或限流），请稍后重试";
        } else {
            hint = "调用 AI 接口失败（模型 " + model + "）：" + (detail == null ? "未知错误" : detail);
        }
        log.warn("AI 调用失败，请求地址：{}{}，模型：{}，原因：{}", baseUrl, chatPath, model, detail);
        return build(HttpStatus.BAD_GATEWAY.value(), hint);
    }

    private int statusCode(Exception e) {
        if (e instanceof RestClientResponseException restClientResponseException) {
            return restClientResponseException.getStatusCode().value();
        }
        // 部分版本会把状态码拼在异常信息里，例如 "401 - {...}"
        String detail = rootMessage(e);
        if (detail != null) {
            var matcher = java.util.regex.Pattern.compile("^\\s*(\\d{3})\\b").matcher(detail);
            if (matcher.find()) {
                return Integer.parseInt(matcher.group(1));
            }
        }
        return -1;
    }

    private boolean isAuthFailure(String detail) {
        // 不同服务商的返回体不一样（InvalidApiKey / invalid_api_key / Authentication Fails ...），统一模糊匹配
        String lower = detail == null ? "" : detail.toLowerCase();
        return lower.contains("401")
                || lower.contains("invalidapikey")
                || lower.contains("invalid api-key")
                || lower.contains("invalid_api_key")
                || lower.contains("authentication fails")
                || lower.contains("incorrect api key");
    }

    private ResponseEntity<Map<String, Object>> build(int status, String message) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("code", status);
        body.put("message", message == null || message.isBlank() ? "请求失败" : message);
        body.put("timestamp", LocalDateTime.now().toString());
        return ResponseEntity.status(status).body(body);
    }

    /** 取最内层异常信息，AI SDK 的真实原因通常在 cause 链末端 */
    private String rootMessage(Throwable throwable) {
        String message = throwable.getMessage();
        Throwable current = throwable;
        while (current != null) {
            if (current.getMessage() != null && !current.getMessage().isBlank()) {
                message = current.getMessage();
            }
            current = current.getCause();
        }
        return message;
    }
}
