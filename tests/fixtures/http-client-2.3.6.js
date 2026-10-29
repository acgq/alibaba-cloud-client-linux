// Unmodified HttpClient module from Alibaba Cloud Client 2.3.6, used to test
// the Linux patch against the upstream request, proxy and error handling.
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", ({ value: true }));
exports.httpxGet = httpxGet;
exports.httpxSend = httpxSend;
const axios_1 = __importDefault(__webpack_require__(/*! axios */ "./node_modules/axios/dist/node/axios.cjs"));
const global_1 = __webpack_require__(/*! ../global */ "./target/main/global.js");
const i18nopt_1 = __importDefault(__webpack_require__(/*! ../i18n/i18nopt */ "./target/main/i18n/i18nopt.js"));
const logger_1 = __importDefault(__webpack_require__(/*! ../logger/logger */ "./target/main/logger/logger.js"));
function httpxGet(url, config) {
    return __awaiter(this, void 0, void 0, function* () {
        config.url = url;
        config.method = "GET";
        return httpxSend(config);
    });
}
function httpxSend(request) {
    return __awaiter(this, void 0, void 0, function* () {
        if (/^https:/i.test(request.url)) {
            const proxy = (0, global_1.getHttpsProxy)();
            return sendRequest(request, proxy);
        }
        else {
            const proxy = (0, global_1.getHttpProxy)();
            return sendRequest(request, proxy);
        }
    });
}
function sendRequest(request, proxy) {
    return __awaiter(this, void 0, void 0, function* () {
        if (proxy != undefined) {
            // noinspection UnnecessaryLocalVariableJS
            const proxyConfig = {
                protocol: proxy.protocol,
                host: proxy.server,
                port: proxy.port,
                auth: proxy.needAuth ? {
                    username: proxy.username,
                    password: proxy.password,
                } : undefined,
            };
            request.proxy = proxyConfig;
        }
        request.validateStatus = status => status == 200 || status >= 400;
        return axios_1.default.request(request).then(response => {
            if (proxy != undefined) {
                logger_1.default.info("proxy %s request success: %s", request.method, request.url);
                if (response.status == 407) {
                    logger_1.default.info("proxy %s request status: 407", request.method);
                    return Promise.reject(normalizeMessage(proxy, { response }));
                }
            }
            return response;
        }).catch(reason => {
            if (proxy != undefined) {
                logger_1.default.warn("proxy %s request %s, failed: %s", request.method, request.url, reason);
                logger_1.default.warn("current proxy: %s://%s:%s", proxy.protocol, proxy.server, proxy.port);
                reason = normalizeMessage(proxy, reason);
            }
            else {
                logger_1.default.warn("httpx %s request %s, failed: %s", request.method, request.url, reason);
            }
            return Promise.reject(reason);
        });
    });
}
function normalizeMessage(proxy, reason) {
    if (reason.response) {
        if (reason.response.statusText == "Proxy Authentication Required") {
            return i18nopt_1.default.t("visitor.proxy.errors.auth", proxy);
        }
    }
    else {
        if (reason.syscall == "getaddrinfo") {
            return i18nopt_1.default.t("visitor.proxy.errors.connect.resolve", proxy);
        }
        if (reason.syscall == "connect") {
            return i18nopt_1.default.t("visitor.proxy.errors.connect.refused", proxy);
        }
    }
    return reason;
}


//# sourceURL=webpack://alibaba-cloud-client/./target/main/local/HttpClient.js?
