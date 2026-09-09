//+------------------------------------------------------------------+
//| JsonHelper.mqh                                                    |
//|                                                                    |
//| MQL5 TIDAK punya JSON parser bawaan. Daripada import library pihak |
//| ketiga (nambah dependency), kita cuma butuh 2 hal dari respons API |
//| (Anthropic/Telegram): (1) ambil isi string dari sebuah key         |
//| tertentu, (2) unescape karakter escape standar JSON (\" \\ \n dst).|
//| Ini BUKAN parser JSON umum -- cuma cukup buat kebutuhan kita:      |
//| respons yang kita baca strukturnya SUDAH KITA TAHU PERSIS (bukan   |
//| JSON sembarang dari user), jadi pendekatan cari-string ini aman &  |
//| jauh lebih ringan daripada bikin/pakai parser penuh.               |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Ubah escape sequence standar JSON (\" \\ \/ \n \r \t) balik jadi  |
//| karakter aslinya. \uXXXX (unicode escape) SENGAJA TIDAK di-handle |
//| -- kalau API mengirim teks non-ASCII, biasanya dikirim sebagai    |
//| UTF-8 mentah (bukan di-escape \u), jadi ini jarang kepakai.        |
//+------------------------------------------------------------------+
string JsonUnescape(const string src)
  {
   string out = "";
   int len = StringLen(src);
   for(int i = 0; i < len; i++)
     {
      ushort ch = StringGetCharacter(src, i);
      if(ch == '\\' && i + 1 < len)
        {
         ushort next = StringGetCharacter(src, i + 1);
         switch(next)
           {
            case '"':  out += "\""; i++; break;
            case '\\': out += "\\"; i++; break;
            case '/':  out += "/";  i++; break;
            case 'n':  out += "\n"; i++; break;
            case 'r':  out += "\r"; i++; break;
            case 't':  out += "\t"; i++; break;
            default:
               // Escape yang tidak dikenal (termasuk \u...) -- biarkan
               // backslash-nya apa adanya, jangan sampai teks hilang.
               out += StringSubstr(src, i, 1);
               break;
           }
        }
      else
        {
         out += StringSubstr(src, i, 1);
        }
     }
   return out;
  }

//+------------------------------------------------------------------+
//| Cari `"<key>":"` di dalam `json`, lalu ambil isinya sampai ketemu  |
//| tanda kutip PENUTUP yang TIDAK di-escape. Balikin "" (string      |
//| kosong) kalau key tidak ketemu -- CEK dengan JsonHasKey() dulu     |
//| kalau perlu bedakan "key tidak ada" vs "key ada tapi isinya        |
//| kosong".                                                           |
//+------------------------------------------------------------------+
string JsonExtractString(const string json, const string key)
  {
   string needle = "\"" + key + "\":\"";
   int start = StringFind(json, needle);
   if(start < 0)
      return "";
   start += StringLen(needle);

   int len = StringLen(json);
   int i = start;
   while(i < len)
     {
      ushort ch = StringGetCharacter(json, i);
      if(ch == '\\')
        {
         i += 2; // lompatin karakter yang di-escape, jangan dianggap penutup
         continue;
        }
      if(ch == '"')
         break;
      i++;
     }

   string raw = StringSubstr(json, start, i - start);
   return JsonUnescape(raw);
  }

//+------------------------------------------------------------------+
//| Cek apakah `"<key>":` ada di dalam json (buat bedain "key tidak    |
//| ada" vs "ada tapi string kosong"). Berguna buat cek field error    |
//| semacam {"error":{"message":"..."}}.                               |
//+------------------------------------------------------------------+
bool JsonHasKey(const string json, const string key)
  {
   return StringFind(json, "\"" + key + "\":") >= 0;
  }

//+------------------------------------------------------------------+
//| Ambil nilai NUMERIK (bukan string berkutip) dari `"<key>":123`.    |
//| Balikin -1 kalau key tidak ketemu. Dipakai buat baca "message_id"  |
//| dari respons Telegram (angka polos, bukan "message_id":"123").    |
//+------------------------------------------------------------------+
long JsonExtractInt(const string json, const string key)
  {
   string needle = "\"" + key + "\":";
   int start = StringFind(json, needle);
   if(start < 0) return -1;
   start += StringLen(needle);

   int len = StringLen(json);
   int i = start;
   while(i < len && StringGetCharacter(json, i) == ' ') i++;

   string numStr = "";
   while(i < len)
     {
      ushort ch = StringGetCharacter(json, i);
      if((ch >= '0' && ch <= '9') || ch == '-') { numStr += StringSubstr(json, i, 1); i++; }
      else break;
     }
   if(numStr == "") return -1;
   return StringToInteger(numStr);
  }
//+------------------------------------------------------------------+
