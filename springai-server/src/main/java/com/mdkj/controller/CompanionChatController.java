package com.mdkj.controller;

import com.mdkj.persona.PersonaPromptService;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.AbstractChatMemoryAdvisor;
import org.springframework.ai.chat.client.advisor.PromptChatMemoryAdvisor;
import org.springframework.ai.chat.memory.InMemoryChatMemory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Flux;

/**
 * 唯一的对话接口：和「张雪香美」聊天。
 *
 * <p>人设只拼一次（见 {@link PersonaPromptService}），每轮只传用户这句话 + 会话 id，
 * 记忆交给 {@link PromptChatMemoryAdvisor}，尽量少花 token。</p>
 */
@RestController
@RequestMapping("/api/v1/chat")
//允许跨域请求
@CrossOrigin
public class CompanionChatController {

    /** 气泡分隔符：模型输出换行，SSE 承载不了，换成它再让前端拆 */
    private static final String BUBBLE_SEP = "\u0001";

    /** 记住最近几条消息，够接上话就行，多了纯烧 token */
    private final int memorySize;

    private final ChatClient chatClient;

    public CompanionChatController(ChatClient.Builder chatClientBuilder,
                                   PersonaPromptService personaPromptService,
                                   @Value("${app.chat.memory-size:10}") int memorySize) {
        this.chatClient = chatClientBuilder
                .defaultSystem(personaPromptService.systemPrompt())
                .defaultAdvisors(new PromptChatMemoryAdvisor(new InMemoryChatMemory()))
                .build();
        this.memorySize = memorySize;
    }

    //普通对话
    @GetMapping("/base")
    public String base(@RequestParam("msg") String msg,
                       @RequestParam(value = "conversationId", defaultValue = "default") String conversationId) {
        return chatClient.prompt()
                .user(msg.trim())
                .advisors(spec -> spec
                        .param(AbstractChatMemoryAdvisor.CHAT_MEMORY_CONVERSATION_ID_KEY, conversationId)
                        .param(AbstractChatMemoryAdvisor.CHAT_MEMORY_RETRIEVE_SIZE_KEY, memorySize))
                .call()
                .content();
    }

    //流式对话：结尾补 [over]，前端收到才关闭 SSE 连接
    @GetMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<String> stream(@RequestParam("msg") String msg,
                               @RequestParam(value = "conversationId", defaultValue = "default") String conversationId) {
        return chatClient.prompt()
                .user(msg.trim())
                .advisors(spec -> spec
                        .param(AbstractChatMemoryAdvisor.CHAT_MEMORY_CONVERSATION_ID_KEY, conversationId)
                        .param(AbstractChatMemoryAdvisor.CHAT_MEMORY_RETRIEVE_SIZE_KEY, memorySize))
                .stream()
                .content()
                // SSE 会把换行当成分帧符吞掉，换成哨兵字符，前端据此拆成多条气泡
                .map(chunk -> chunk.replace("\r\n", BUBBLE_SEP).replace("\n", BUBBLE_SEP))
                .concatWith(Flux.just("[over]"));
    }
}
