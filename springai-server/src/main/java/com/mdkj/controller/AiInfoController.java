package com.mdkj.controller;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 当前配置，用来确认「这玩意儿到底在调谁」。不返回 Key，只说有没有配。
 */
@RestController
@RequestMapping("/api/v1/info")
@CrossOrigin
public class AiInfoController {

    private final String baseUrl;
    private final String chatPath;
    private final String chatModel;
    private final String openAiKey;

    public AiInfoController(@Value("${spring.ai.openai.base-url:}") String baseUrl,
                            @Value("${spring.ai.openai.chat.completions-path:/v1/chat/completions}") String chatPath,
                            @Value("${spring.ai.openai.chat.options.model:}") String chatModel,
                            @Value("${spring.ai.openai.api-key:}") String openAiKey) {
        this.baseUrl = baseUrl;
        this.chatPath = chatPath;
        this.chatModel = chatModel;
        this.openAiKey = openAiKey;
    }

    @GetMapping
    public Map<String, Object> info() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("protocol", "OpenAI 兼容");
        body.put("persona", "张雪香美（大猪头）");
        body.put("baseUrl", baseUrl);
        body.put("chatPath", chatPath);
        body.put("chatUrl", baseUrl + chatPath);
        body.put("model", chatModel);
        body.put("apiKeyConfigured", configured(openAiKey));
        return body;
    }

    /** 占位值不算配置过 */
    private boolean configured(String key) {
        return key != null && !key.isBlank() && !"not-configured".equals(key);
    }
}
