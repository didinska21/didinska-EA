//+------------------------------------------------------------------+
//| AnthropicApi.mqh                                                   |
//|                                                                    |
//| Panggil Anthropic Messages API (https://api.anthropic.com/v1/     |
//| messages) lewat WebRequest() bawaan MQL5. PENTING: WebRequest itu  |
//| BLOCKING (synchronous) -- selama menunggu respons, EA (dan         |
//| terminal MT5) tertahan. Makanya di EA utama, tiap panggilan analis |
//| dipecah jadi 1 langkah state machine terpisah (lewat OnTimer),     |
//| BUKAN dipanggil 10x berturut-turut dalam satu fungsi -- supaya     |
//| jeda antar panggilan kasih kesempatan terminal "bernapas".         |
//|                                                                    |
//| SEBELUM INI BISA JALAN: buka MT5 -> Tools -> Options -> Expert     |
//| Advisors -> centang "Allow WebRequest for listed URL" -> tambahkan |
//| persis: https://api.anthropic.com                                 |
//| (dan https://api.telegram.org buat notifikasi Telegram).           |
//+------------------------------------------------------------------+
#property strict
#include "JsonHelper.mqh"

#define ANTHROPIC_API_URL "https://api.anthropic.com/v1/messages"
#define ANTHROPIC_API_VERSION "2023-06-01"

//+------------------------------------------------------------------+
//| Escape string biar aman dimasukkan ke dalam nilai string JSON     |
//| (kebalikan dari JsonUnescape di JsonHelper.mqh) -- dipakai buat    |
//| system prompt & data yang KITA KIRIM, karena bisa aja mengandung  |
//| tanda kutip, newline, dll yang harus di-escape biar JSON valid.    |
//+------------------------------------------------------------------+
string JsonEscape(const string src)
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
            out += StringSubstr(src, i, 1);
            break;
        }
     }
   return out;
  }

//+------------------------------------------------------------------+
//| Panggil Anthropic Messages API 1x (1 system prompt + 1 pesan user, |
//| tanpa histori percakapan -- tiap analis "mulai dari nol" persis    |
//| seperti versi Worker/Groq-nya). Balikin true kalau sukses & teks   |
//| jawaban AI ditaruh di `outText`; false kalau gagal & alasannya di  |
//| `outError`.                                                        |
//+------------------------------------------------------------------+
bool AnthropicChatCall(const string apiKey,
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
   body += "\"model\":\""      + JsonEscape(model)      + "\",";
   body += "\"max_tokens\":"   + IntegerToString(maxTokens) + ",";
   body += "\"system\":\""     + JsonEscape(systemPrompt) + "\",";
   body += "\"messages\":[{\"role\":\"user\",\"content\":\"" + JsonEscape(userContent) + "\"}]";
   body += "}";

   string headers = "content-type: application/json\r\n";
   headers += "x-api-key: " + apiKey + "\r\n";
   headers += "anthropic-version: " + ANTHROPIC_API_VERSION + "\r\n";

   uchar postData[];
   int bodyLen = StringToCharArray(body, postData, 0, StringLen(body), CP_UTF8);
   // FIX (sama bug seperti OpenAiCompatibleApi.mqh): `count` di atas diisi
   // eksplisit (StringLen(body), bukan -1), jadi StringToCharArray TIDAK
   // menambahkan null-terminator ke array -- postData sudah pas panjangnya.
   // JANGAN ArrayResize(postData, bodyLen-1) di sini -- itu memotong byte
   // TERAKHIR body asli (karakter '}' penutup JSON), bikin request selalu
   // gagal dengan error provider "unexpected end of JSON input".

   uchar result[];
   string resultHeaders;

   ResetLastError();
   int status = WebRequest("POST", ANTHROPIC_API_URL, headers, timeoutMs, postData, result, resultHeaders);

   if(status == -1)
     {
      int err = GetLastError();
      if(err == 4060)
         outError = StringFormat("WebRequest gagal (error 4060): URL %s belum di-whitelist. Buka Tools > Options > Expert Advisors > Allow WebRequest, tambahkan URL itu.", ANTHROPIC_API_URL);
      else
         outError = StringFormat("WebRequest gagal, error code=%d", err);
      return false;
     }

   string responseBody = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);

   if(status != 200)
     {
      string apiErrMsg = JsonExtractString(responseBody, "message");
      outError = StringFormat("Anthropic API balas HTTP %d: %s", status, apiErrMsg != "" ? apiErrMsg : responseBody);
      return false;
     }

   // Respons sukses bentuknya:
   // {"content":[{"type":"text","text":"...jawaban AI..."}], ...}
   // Ambil field "text" pertama yang ketemu -- cukup buat kasus kita
   // (tidak pakai tool-calling, jadi selalu 1 blok teks).
   string text = JsonExtractString(responseBody, "text");
   if(text == "")
     {
      outError = "Respons Anthropic tidak mengandung field 'text' yang bisa dibaca. Raw: " + responseBody;
      return false;
     }

   outText = text;
   return true;
  }
//+------------------------------------------------------------------+
