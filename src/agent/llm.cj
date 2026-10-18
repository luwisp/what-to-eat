package huaiwei.agent

import huaiwei.model.*
import huaiwei.platform.*
import std.env.*
import std.net.*
import std.sync.*
import stdx.net.http.*
import stdx.net.tls.*
import stdx.encoding.url.*
import stdx.encoding.json.*

public interface LLMClient {
    func complete(messages: Array<JsonObject>, tools: Array<JsonObject>, deadline: Deadline): Outcome<JsonObject>
}

public class ModelConfig {
    public let key: String
    public let baseUrl: String
    public let model: String
    public init(key: String, baseUrl: String, model: String) {
        this.key = key
        this.baseUrl = baseUrl
        this.model = model
    }
    public func enabled(): Bool {
        !key.isEmpty() && !baseUrl.isEmpty() && !model.isEmpty()
    }
}

public func modelConfigFromEnvironment(): ModelConfig {
    ModelConfig(getVariable("DEEPSEEK_API_KEY") ?? "", getVariable("DEEPSEEK_BASE_URL") ?? "https://api.deepseek.com",
        getVariable("DEEPSEEK_MODEL") ?? "")
}

class NetworkRequest {
    let lock = Mutex()
    var socket: ?TcpSocket = None
    var cancelled = false
    func connect(address: SocketAddress, deadline: Deadline): StreamingSocket {
        let connection = TcpSocket(address)
        synchronized(lock) {
            if (cancelled || deadline.remainingMillis() <= 0) {
                connection.close();
                throw Exception("Request cancelled")
            }
            socket = Some(connection)
        }
        connection.connect(timeout: deadline.remainingMillis() * Duration.millisecond)
        return connection
    }
    func cancel(): Unit {
        synchronized(lock) {
            cancelled = true
            if (let Some(connection) <- socket) {
                connection.close()
            }
        }
    }
}

public class HttpLLMClient <: LLMClient {
    let config: ModelConfig
    public init(config: ModelConfig) {
        this.config = config
    }
    public func complete(messages: Array<JsonObject>, tools: Array<JsonObject>, deadline: Deadline): Outcome<JsonObject> {
        if (!config.enabled()) {
            return Outcome.Err(DomainError("MODEL_DISABLED", "未配置模型"))
        }
        let remaining = deadline.remainingMillis()
        if (remaining <= 0) {
            return Outcome.Err(DomainError("MODEL_TIMEOUT", "模型等待已超时"))
        }
        let state = NetworkRequest()
        try {
            let url = URL.parse(config.baseUrl)
            if (url.scheme != "https" && !(url.scheme == "http" && ["127.0.0.1", "localhost"].contains(url.hostName))) {
                return Outcome.Err(DomainError("MODEL_CONFIG", "模型地址须使用HTTPS"))
            }
            var tls = TlsClientConfig();
            tls.serverName = Some(url.hostName)
            let client = ClientBuilder()
                .autoRedirect(false)
                .tlsConfig(tls)
                .readTimeout(remaining * Duration.millisecond)
                .writeTimeout(remaining * Duration.millisecond)
                .connector({address => state.connect(address, deadline)})
                .build()
            let body = JsonObject();
            body.put("model", JsonString(config.model))
            body.put("messages", JsonArray(messages.map<JsonValue>({m => m})))
            body.put("stream", JsonBool(false));
            body.put("max_tokens", JsonInt(2048))
            if (!tools.isEmpty()) {
                body.put("tools", JsonArray(tools.map<JsonValue>({t => t})))
            } else {
                body.put("response_format", JsonValue.fromStr("{\"type\":\"json_object\"}"))
            }
            let endpoint = if (config.baseUrl.endsWith("/")) {
                config.baseUrl + "chat/completions"
            } else {
                config.baseUrl + "/chat/completions"
            }
            let future = spawn {
                try {
                    let response = client.send(
                        HttpRequestBuilder()
                            .method("POST")
                            .url(endpoint)
                            .header("authorization", "Bearer ${config.key}")
                            .header("content-type", "application/json")
                            .body(body.toString())
                            .build())
                    if (response.status == 401 || response.status == 403) {
                        return Outcome<JsonObject>.Err(DomainError("MODEL_AUTH", "模型认证失败"))
                    }
                    if (response.status != 200) {
                        return Outcome<JsonObject>.Err(DomainError("MODEL_HTTP", "模型服务暂不可用"))
                    }
                    let result = JsonValue.fromStr(readLimited(response.body, limit: 1048576)).asObject()
                    return Outcome.Ok(result["choices"].asArray()[0].asObject()["message"].asObject())
                } catch (_: Exception) {
                    return Outcome<JsonObject>.Err(DomainError("MODEL_RESPONSE", "模型响应无效或网络中断"))
                } finally {
                    state.cancel();
                    client.close()
                }
            }
            try {
                let wait = deadline.remainingMillis()
                if (wait <= 0) {
                    state.cancel();
                    client.close();
                    future.cancel();
                    return Outcome.Err(DomainError("MODEL_TIMEOUT", "模型等待已超时"))
                }
                return future.get(wait * Duration.millisecond)
            } catch (_: TimeoutException) {
                state.cancel();
                client.close();
                future.cancel()
                return Outcome.Err(DomainError("MODEL_TIMEOUT", "模型等待已超时"))
            }
        } catch (_: Exception) {
            state.cancel();
            return Outcome.Err(DomainError("MODEL_CONFIG", "模型配置或网络不可用"))
        }
    }
}

public func modelMessage(role: String, content: String): JsonObject {
    let obj = JsonObject();
    obj.put("role", JsonString(role));
    obj.put("content", JsonString(content));
    obj
}
