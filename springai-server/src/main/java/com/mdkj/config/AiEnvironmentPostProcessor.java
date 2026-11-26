package com.mdkj.config;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.env.EnvironmentPostProcessor;
import org.springframework.core.Ordered;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.MapPropertySource;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 让「填一个 URL + Key + 模型名」就能对接任何 OpenAI 兼容接口。
 *
 * <p>Spring AI 的 OpenAI 客户端会把 {@code base-url} 和固定的 {@code /v1/chat/completions}
 * 拼在一起，但各家文档给的 base_url 写法并不统一：</p>
 * <ul>
 *   <li>{@code https://api.deepseek.com}            —— 不带版本号</li>
 *   <li>{@code https://api.moonshot.cn/v1}          —— 带 /v1</li>
 *   <li>{@code https://open.bigmodel.cn/api/paas/v4}—— 带 /v4</li>
 *   <li>{@code https://dashscope.aliyuncs.com/compatible-mode} —— 不带版本号</li>
 * </ul>
 *
 * <p>如果直接把这些值丢给 Spring AI，带 {@code /v1} 的地址会被拼成
 * {@code /v1/v1/chat/completions}，带 {@code /v4} 的地址会 404。这里在配置绑定之前
 * 把用户填的地址拆成「服务根地址 + 版本前缀」，再算出正确的请求路径，用户怎么填都能用。
 * 想完全自己控制时，可以额外设置 {@code AI_CHAT_PATH}。</p>
 */
public class AiEnvironmentPostProcessor implements EnvironmentPostProcessor, Ordered {

    /** 默认仍然指向阿里云百炼的 OpenAI 兼容模式，老用户升级后无需改任何配置 */
    static final String DEFAULT_BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode";

    private static final String BASE_URL_PROP = "spring.ai.openai.base-url";
    private static final String CHAT_PATH_PROP = "spring.ai.openai.chat.completions-path";

    @Override
    public void postProcessEnvironment(ConfigurableEnvironment environment, SpringApplication application) {
        String rawBaseUrl = firstNonBlank(
                environment.getProperty("AI_BASE_URL"),
                environment.getProperty(BASE_URL_PROP),
                DEFAULT_BASE_URL);

        Endpoint endpoint = Endpoint.parse(rawBaseUrl);

        Map<String, Object> overrides = new LinkedHashMap<>();
        overrides.put(BASE_URL_PROP, endpoint.baseUrl());
        overrides.put(CHAT_PATH_PROP, path(environment.getProperty("AI_CHAT_PATH"), endpoint.chatPath()));

        // addFirst：优先级高于 application.yml 和系统环境变量，配置绑定一定用我们算出来的值
        environment.getPropertySources().addFirst(new MapPropertySource("aiEndpointNormalizer", overrides));
    }

    @Override
    public int getOrder() {
        // 必须排在 ConfigDataEnvironmentPostProcessor 之后，才能读到 application.yml 里的值
        return Ordered.LOWEST_PRECEDENCE;
    }

    private static String path(String override, String fallback) {
        if (override == null || override.isBlank()) {
            return fallback;
        }
        String value = override.trim();
        return value.startsWith("/") ? value : "/" + value;
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) {
                return value.trim();
            }
        }
        return "";
    }

    /**
     * 拆解后的接口地址。
     *
     * @param baseUrl  传给 Spring AI 的服务根地址（不带版本号）
     * @param chatPath 对话接口路径，如 {@code /v1/chat/completions}
     */
    record Endpoint(String baseUrl, String chatPath) {

        static Endpoint parse(String raw) {
            String url = raw == null ? "" : raw.trim();
            while (url.endsWith("/")) {
                url = url.substring(0, url.length() - 1);
            }

            // 用户直接粘了完整的对话地址：https://host/v1/chat/completions
            if (url.endsWith("/chat/completions")) {
                String prefix = url.substring(0, url.length() - "/chat/completions".length());
                int slash = prefix.lastIndexOf('/');
                if (slash > 0) {
                    String version = prefix.substring(slash);
                    if (isVersionSegment(version.substring(1))) {
                        return new Endpoint(prefix.substring(0, slash), url.substring(slash));
                    }
                }
                return new Endpoint(prefix, "/chat/completions");
            }

            int slash = url.lastIndexOf('/');
            if (slash > 0) {
                String lastSegment = url.substring(slash + 1);
                if (isVersionSegment(lastSegment)) {
                    return new Endpoint(url.substring(0, slash), "/" + lastSegment + "/chat/completions");
                }
            }
            return new Endpoint(url, "/v1/chat/completions");
        }

        /** v1 / v4 / v1beta / v2.1 这类版本号 */
        private static boolean isVersionSegment(String segment) {
            return segment.matches("^[vV]\\d+([.\\-]?[a-zA-Z0-9]+)*$");
        }
    }
}
