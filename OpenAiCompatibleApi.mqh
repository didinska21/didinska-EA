//+------------------------------------------------------------------+
//| OpenAiCompatibleApi.mqh                                            |
//|                                                                    |
//| Wrapper UNIVERSAL buat provider mana pun yang ikutin format OpenAI |
//| "Chat Completions" (POST {model, messages:[...]}, auth lewat       |
//| header "Authorization: Bearer <key>") -- ini format yang dipakai   |
//| Groq, OpenRouter, dan hampir semua platform aggregator AI          |
//| (termasuk yang kasih akses ke Gemini/GLM/DeepSeek/GPT/Qwen/Muse    |
//| Spark lewat 1 API key). Beda dari AnthropicApi.mqh yang formatnya  |
//| Anthropic-spesifik (system terpisah, header x-api-key, dst).       |
//|                                                                    |
//| `baseUrl` HARUS diisi PERSIS endpoint chat-completions provider    |
//| kamu, contoh:                                                      |
//|   Groq:       https://api.groq.com/openai/v1/chat/completions      |
//|   OpenRouter: https://openrouter.ai/api/v1/chat/completions        |
//| Cek dashboard/dokumentasi provider kamu buat tahu persis URL-nya.  |
//|                                                                    |
//| FIX (2026-09-09):                                                  |
//| 1. Bug ArrayResize(postData, bodyLen-1) DIHAPUS -- StringToCharArray|
//|    dipanggil dengan parameter `count` diisi eksplisit (bukan -1),  |
//|    yang berarti MQL5 TIDAK menambahkan null-terminator ke array.   |
//|    Trimming byte terakhir yang lama JUSTRU memotong karakter '}'   |
//|    penutup JSON, bikin SEMUA request selalu gagal dengan provider  |
//|    error "unexpected end of JSON input".                          |
//| 2. OpenAiJsonEscape() diperbaiki supaya aman untuk emoji/karakter  |
//|    di luar BMP (surrogate pair UTF-16) -- sebelumnya bisa kepotong |
//|    kalau opini AI mengandung emoji, dan control character < 0x20  |
//|    sekarang di-escape jadi \u00XX (dulu lolos mentah).             |
//+------------------------------------------------------------------+
#property strict
#include "JsonHelper.mqh"

//+------------------------------------------------------------------+
//| Escape string biar aman jadi nilai string di dalam JSON.           |
//| Aman untuk surrogate pair (emoji dsb) dan control character.       |
//+------------------------------------------------------------------+
string OpenAiJsonEscape(const string src)
  {
   string out = "";
   int len = StringLen(src);
   for(int i = 0; i < len; i++)
     {
      ushort ch = StringGetCharacter(src, i);
      switch(ch)
        {
         case '"':  out += "\\\""; break;
         case '\\': out += "\\\\"; break;
         case '\n': out += "\\n";  break;
         case '\r': out += "\\r";  break;
         case '\t': out += "\\t";  break;
         default:
            if(ch < 0x20)
              {
               // Control character lain (mis. \b \f atau sampah dari API) --
               // JSON strict tidak terima raw control char, wajib di-escape.
               out += StringFormat("\\u%04x", ch);
              }
            else if(ch >= 0xD800 && ch <= 0xDBFF && (i + 1) < len)
              {
               // High surrogate -- separuh pertama dari 1 emoji/karakter
               // astral. Ambil sekaligus dengan low surrogate pasangannya,
               // jangan dipotong sendirian (kalau kepotong, konversi ke
               // UTF-8 di StringToCharArray bisa gagal/berhenti di tengah).
               out += StringSubstr(src, i, 2);
               i++; // skip low surrogate; i++ di for-loop majuin 1 lagi
              }
            else
              {
               out += StringSubstr(src, i, 1);
              }
            break;
        }
     }
   return out;
  }

//+------------------------------------------------------------------+
//| Panggil endpoint chat/completions 1x (1 system + 1 user message,   |
//| tanpa histori -- sama seperti AnthropicChatCall). Balikin true      |
//| kalau sukses & teksnya ditaruh di outText; false + alasan di        |
//| outError kalau gagal.                                               |
//+------------------------------------------------------------------+
bool OpenAiCompatibleChatCall(const string baseUrl,
                              const string apiKey,
                              const string model,
                              const int    maxTokens,
                              const string systemPrompt,
                              const string userContent,
                              const int    timeoutMs,
                              string      &outText,
                              string      &outError)
  {
   outText  = "";
   outError = "";

   string body = "{";
   body += "\"model\":\""      + OpenAiJsonEscape(model) + "\",";
   // "max_completion_tokens" -- nama parameter resmi Groq/OpenAI saat ini.
   // "max_tokens" versi lama SUDAH DEPRECATED (masih jalan di beberapa
   // model tapi sewaktu-waktu bisa dihapus provider), jadi dihindari.
   body += "\"max_completion_tokens\":" + IntegerToString(maxTokens) + ",";
   body += "\"messages\":[";
   body += "{\"role\":\"system\",\"content\":\"" + OpenAiJsonEscape(systemPrompt) + "\"},";
   body += "{\"role\":\"user\",\"content\":\""   + OpenAiJsonEscape(userContent)  + "\"}";
   body += "]}";

   string headers = "content-type: application/json\r\n";
   headers += "authorization: Bearer " + apiKey + "\r\n";

   uchar postData[];
   int bodyLen = StringToCharArray(body, postData, 0, StringLen(body), CP_UTF8);
   // PENTING: `count` di atas diisi eksplisit (StringLen(body), bukan -1),
   // jadi StringToCharArray TIDAK menambahkan null-terminator ke array --
   // postData sudah pas panjangnya. JANGAN ArrayResize(postData, bodyLen-1)
   // di sini -- itu bug lama yang memotong byte terakhir body (karakter '}'
   // penutup JSON) dan bikin SEMUA request gagal dengan provider error
   // "unexpected end of JSON input".

   uchar result[];
   string resultHeaders;

   ResetLastError();
   int status = WebRequest("POST", baseUrl, headers, timeoutMs, postData, result, resultHeaders);

   if(status == -1)
     {
      int err = GetLastError();
      if(err == 4060)
         outError = StringFormat("WebRequest gagal (error 4060): URL %s belum di-whitelist. Buka Tools > Options > Expert Advisors > Allow WebRequest, tambahkan URL itu.", baseUrl);
      else
         outError = StringFormat("WebRequest gagal, error code=%d", err);
      return false;
     }

   string responseBody = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);

   if(status != 200)
     {
      string apiErrMsg = JsonExtractString(responseBody, "message");
      outError = StringFormat("Provider balas HTTP %d: %s", status, apiErrMsg != "" ? apiErrMsg : responseBody);
      return false;
     }

   // Respons sukses bentuknya:
   // {"choices":[{"message":{"role":"assistant","content":"...jawaban AI..."}}], ...}
   // JsonExtractString cari "content":" pertama yang ketemu -- untuk
   // format ini itu SUDAH TEPAT isi jawaban asisten (bukan system/user
   // message kita sendiri, karena itu di object request yang beda, bukan
   // di responseBody).
   string text = JsonExtractString(responseBody, "content");
   if(text == "")
     {
      outError = "Respons provider tidak mengandung field 'content' yang bisa dibaca. Raw: " + responseBody;
      return false;
     }

   outText = text;
   return true;
  }
//+------------------------------------------------------------------+
