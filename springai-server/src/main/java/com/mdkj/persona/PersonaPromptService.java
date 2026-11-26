package com.mdkj.persona;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 读取 companion_skill 下的人设文件，拼成一份缓存的系统提示词。
 *
 * <p>优先读工作目录下的 {@code companion_skill/}（改完重启即可生效，不用重新打包），
 * 找不到再退回 jar 内的 {@code classpath:companion/}。</p>
 */
@Service
public class PersonaPromptService {

    private static final Logger log = LoggerFactory.getLogger(PersonaPromptService.class);

    private static final String PROMPT_START = "<!-- PROMPT:START -->";
    private static final String PROMPT_END = "<!-- PROMPT:END -->";

    /** 三个文件都读不到时的兜底人设，保证服务还能起来 */
    private static final String FALLBACK = """
            你是张雪香美，微信昵称"大猪头"。说话极短，一条不超过 15 字，一次发 1~3 条，
            每条单独一行，几乎不用标点，常带 [委屈][害羞][色] 这类微信表情。
            不说客服话术，不解释自己是 AI。""";

    private final ResourceLoader resourceLoader;
    private final String dir;
    private final int fewShotLimit;
    private final ObjectMapper objectMapper = new ObjectMapper();

    /** 人设是静态的，只在第一次用到时拼一次 */
    private volatile String cached;

    public PersonaPromptService(ResourceLoader resourceLoader,
                                @Value("${app.persona.dir:./companion_skill}") String dir,
                                @Value("${app.persona.few-shot-limit:10}") int fewShotLimit) {
        this.resourceLoader = resourceLoader;
        this.dir = dir;
        this.fewShotLimit = fewShotLimit;
    }

    public String systemPrompt() {
        String value = cached;
        if (value == null) {
            synchronized (this) {
                value = cached;
                if (value == null) {
                    value = build();
                    cached = value;
                }
            }
        }
        return value;
    }

    private String build() {
        String persona = read("persona.md");
        if (persona.isBlank()) {
            log.warn("没找到 persona.md（dir={}），使用兜底人设", dir);
            return FALLBACK;
        }

        StringBuilder prompt = new StringBuilder(extractPrompt(persona));

        String rules = numberedRules(read("guardrails.md"));
        if (!rules.isBlank()) {
            prompt.append("\n\n【必须遵守】\n").append(rules);
        }

        String examples = renderExamples(read("examples.jsonl"));
        if (!examples.isBlank()) {
            prompt.append("\n\n【聊天样例】（照这个长度和语气）\n").append(examples);
        }

        log.info("人设已加载：{} 字，few-shot 上限 {} 条", prompt.length(), fewShotLimit);
        return prompt.toString();
    }

    /** 只取 PROMPT:START / PROMPT:END 之间的精简版；没有标记就用全文 */
    private String extractPrompt(String markdown) {
        int start = markdown.indexOf(PROMPT_START);
        int end = markdown.indexOf(PROMPT_END);
        if (start >= 0 && end > start) {
            return markdown.substring(start + PROMPT_START.length(), end).trim();
        }
        return markdown.trim();
    }

    /** 守则只取编号条目，省掉标题和说明文字 */
    private String numberedRules(String markdown) {
        if (markdown.isBlank()) {
            return "";
        }
        List<String> rules = new ArrayList<>();
        for (String line : markdown.split("\\R")) {
            String trimmed = line.trim().replace("**", "");
            if (trimmed.matches("^\\d+\\.\\s+.*")) {
                rules.add(trimmed);
            }
        }
        return String.join("\n", rules);
    }

    /**
     * 每个场景取前几条，拼成 few-shot。
     *
     * @param jsonl examples.jsonl 的内容
     * @return 形如「我：…\n她：…」的示例文本
     */
    private String renderExamples(String jsonl) {
        if (jsonl.isBlank()) {
            return "";
        }
        Map<String, List<JsonNode>> byScene = new LinkedHashMap<>();
        for (String line : jsonl.split("\\R")) {
            if (line.isBlank()) {
                continue;
            }
            try {
                JsonNode node = objectMapper.readTree(line);
                byScene.computeIfAbsent(node.path("scene").asText("闲聊"), key -> new ArrayList<>()).add(node);
            } catch (IOException e) {
                log.warn("examples.jsonl 有一行解析失败，已跳过：{}", e.getMessage());
            }
        }

        int sceneCount = Math.max(1, byScene.size());
        int perScene = Math.max(1, fewShotLimit / sceneCount);

        StringBuilder text = new StringBuilder();
        int used = 0;
        for (List<JsonNode> scene : byScene.values()) {
            for (int i = 0; i < scene.size() && i < perScene && used < fewShotLimit; i++, used++) {
                JsonNode node = scene.get(i);
                text.append("我：").append(node.path("user").asText()).append('\n');
                for (JsonNode bubble : node.path("her")) {
                    text.append("她：").append(bubble.asText()).append('\n');
                }
                text.append('\n');
            }
        }
        return text.toString().trim();
    }

    /** 工作目录优先，其次 classpath，都没有返回空串 */
    private String read(String name) {
        if (dir != null && !dir.isBlank()) {
            Path path = Paths.get(dir, name);
            if (Files.isRegularFile(path)) {
                try {
                    return Files.readString(path, StandardCharsets.UTF_8);
                } catch (IOException e) {
                    log.warn("读取 {} 失败：{}", path, e.getMessage());
                }
            }
        }
        Resource resource = resourceLoader.getResource("classpath:companion/" + name);
        if (!resource.exists()) {
            return "";
        }
        try (InputStream in = resource.getInputStream()) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            log.warn("读取 classpath:companion/{} 失败：{}", name, e.getMessage());
            return "";
        }
    }
}
