//+------------------------------------------------------------------+
//| TelegramApi.mqh                                                    |
//|                                                                    |
//| Kirim notifikasi Telegram SATU ARAH (EA -> Telegram saja, TIDAK    |
//| menerima command balik/tidak ada polling getUpdates) -- sesuai     |
//| keputusan: bot Telegram interaktif TIDAK dipertahankan di versi EA |
//| ini, cukup notifikasi.                                             |
//|                                                                    |
//| SEBELUM INI BISA JALAN: whitelist juga https://api.telegram.org di |
//| Tools > Options > Expert Advisors > Allow WebRequest (sama seperti |
//| AnthropicApi.mqh).                                                 |
//+------------------------------------------------------------------+
#property strict
#include "JsonHelper.mqh"

//+------------------------------------------------------------------+
//| Kirim 1 pesan teks ke chat Telegram tertentu. Balikin true kalau   |
//| sukses terkirim (HTTP 200 & field "ok":true di respons Telegram).  |
//| Dipanggil best-effort -- gagal kirim Telegram TIDAK BOLEH sampai   |
//| menghentikan alur trading EA, cuma di-log lewat Print().           |
//+------------------------------------------------------------------+
bool TelegramSendMessage(const string botToken, const string chatId, const string text)
  {
   if(botToken == "" || chatId == "")
     {
      Print("[Telegram] botToken/chatId kosong, notifikasi dilewati.");
      return false;
     }

   string url = "https://api.telegram.org/bot" + botToken + "/sendMessage";

   // Escape manual buat JSON (sama seperti JsonEscape di AnthropicApi.mqh,
   // ditulis ulang di sini biar file ini berdiri sendiri/tidak saling
   // depend ke AnthropicApi.mqh).
   string escaped = "";
   int len = StringLen(text);
   for(int i = 0; i < len; i++)
     {
      ushort ch = StringGetCharacter(text, i);
      switch(ch)
        {
         case '"':  escaped += "\\\""; break;
         case '\\': escaped += "\\\\"; break;
         case '\n': escaped += "\\n";  break;
         case '\r': escaped += "\\r";  break;
         case '\t': escaped += "\\t";  break;
         default:   escaped += StringSubstr(text, i, 1); break;
        }
     }

   string body = "{\"chat_id\":\"" + chatId + "\",\"text\":\"" + escaped + "\",\"parse_mode\":\"HTML\",\"disable_web_page_preview\":true}";

   string headers = "content-type: application/json\r\n";

   uchar postData[];
   int bodyLen = StringToCharArray(body, postData, 0, StringLen(body), CP_UTF8);
   // FIX: `count` diisi eksplisit -> StringToCharArray TIDAK menambahkan
   // null-terminator, jadi postData sudah pas panjangnya. ArrayResize(
   // postData, bodyLen-1) yang lama memotong byte TERAKHIR body asli
   // (karakter '}' penutup JSON), bikin request Telegram gagal/berpotensi
   // ditolak sebagai body JSON tidak valid -- JANGAN dipanggil di sini.

   uchar result[];
   string resultHeaders;

   ResetLastError();
   int status = WebRequest("POST", url, headers, 10000, postData, result, resultHeaders);

   if(status == -1)
     {
      int err = GetLastError();
      if(err == 4060)
         Print("[Telegram] WebRequest gagal (4060): https://api.telegram.org belum di-whitelist.");
      else
         Print(StringFormat("[Telegram] WebRequest gagal, error code=%d", err));
      return false;
     }

   string responseBody = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);

   if(status != 200 || StringFind(responseBody, "\"ok\":true") < 0)
     {
      Print(StringFormat("[Telegram] Gagal kirim pesan (HTTP %d): %s", status, responseBody));
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Escape teks buat aman jadi nilai string JSON (dipakai fungsi di    |
//| bawah, ditulis ulang di sini biar file ini tetap berdiri sendiri). |
//+------------------------------------------------------------------+
string TelegramJsonEscape(const string text)
  {
   string escaped = "";
   int len = StringLen(text);
   for(int i = 0; i < len; i++)
     {
      ushort ch = StringGetCharacter(text, i);
      switch(ch)
        {
         case '"':  escaped += "\\\""; break;
         case '\\': escaped += "\\\\"; break;
         case '\n': escaped += "\\n";  break;
         case '\r': escaped += "\\r";  break;
         case '\t': escaped += "\\t";  break;
         default:   escaped += StringSubstr(text, i, 1); break;
        }
     }
   return escaped;
  }

//+------------------------------------------------------------------+
//| Sama seperti TelegramSendMessage(), tapi juga balikin message_id   |
//| hasil kirim (dipakai buat nge-edit pesan yang sama nanti lewat     |
//| TelegramEditMessage(), biar progres 10 analis + Penyimpul tampil   |
//| di 1 pesan yang di-update terus, bukan spam banyak pesan).         |
//+------------------------------------------------------------------+
bool TelegramSendMessageEx(const string botToken, const string chatId, const string text, long &outMessageId)
  {
   outMessageId = -1;
   if(botToken == "" || chatId == "")
     {
      Print("[Telegram] botToken/chatId kosong, notifikasi dilewati.");
      return false;
     }

   string url = "https://api.telegram.org/bot" + botToken + "/sendMessage";
   string body = "{\"chat_id\":\"" + chatId + "\",\"text\":\"" + TelegramJsonEscape(text) +
                 "\",\"parse_mode\":\"HTML\",\"disable_web_page_preview\":true}";
   string headers = "content-type: application/json\r\n";

   uchar postData[];
   int bodyLen = StringToCharArray(body, postData, 0, StringLen(body), CP_UTF8);
   // FIX: lihat catatan di TelegramSendMessage() -- JANGAN ArrayResize
   // (postData, bodyLen-1) di sini, itu memotong '}' penutup JSON asli.

   uchar result[];
   string resultHeaders;
   ResetLastError();
   int status = WebRequest("POST", url, headers, 10000, postData, result, resultHeaders);
   if(status == -1)
     {
      int err = GetLastError();
      Print(StringFormat("[Telegram] WebRequest gagal, error code=%d", err));
      return false;
     }

   string responseBody = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   if(status != 200 || StringFind(responseBody, "\"ok\":true") < 0)
     {
      Print(StringFormat("[Telegram] Gagal kirim pesan (HTTP %d): %s", status, responseBody));
      return false;
     }

   outMessageId = JsonExtractInt(responseBody, "message_id");
   return true;
  }

//+------------------------------------------------------------------+
//| Edit teks pesan Telegram yang sudah terkirim sebelumnya (butuh     |
//| message_id dari TelegramSendMessageEx). Best-effort -- kalau gagal |
//| (misal isi persis sama/"message is not modified"), tidak dianggap  |
//| error fatal, cukup di-log.                                         |
//+------------------------------------------------------------------+
bool TelegramEditMessage(const string botToken, const string chatId, const long messageId, const string text)
  {
   if(botToken == "" || chatId == "" || messageId <= 0) return false;

   string url = "https://api.telegram.org/bot" + botToken + "/editMessageText";
   string body = "{\"chat_id\":\"" + chatId + "\",\"message_id\":" + IntegerToString(messageId) +
                 ",\"text\":\"" + TelegramJsonEscape(text) + "\",\"parse_mode\":\"HTML\",\"disable_web_page_preview\":true}";
   string headers = "content-type: application/json\r\n";

   uchar postData[];
   int bodyLen = StringToCharArray(body, postData, 0, StringLen(body), CP_UTF8);
   // FIX: lihat catatan di TelegramSendMessage() -- JANGAN ArrayResize
   // (postData, bodyLen-1) di sini, itu memotong '}' penutup JSON asli.

   uchar result[];
   string resultHeaders;
   ResetLastError();
   int status = WebRequest("POST", url, headers, 10000, postData, result, resultHeaders);
   if(status == -1)
     {
      Print(StringFormat("[Telegram] Edit gagal, error code=%d", GetLastError()));
      return false;
     }

   string responseBody = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   if(status != 200 || StringFind(responseBody, "\"ok\":true") < 0)
     {
      // "message is not modified" itu wajar (isi sama persis) -- bukan error nyata.
      if(StringFind(responseBody, "message is not modified") < 0)
         Print(StringFormat("[Telegram] Gagal edit pesan (HTTP %d): %s", status, responseBody));
      return false;
     }
   return true;
  }
//+------------------------------------------------------------------+
