-- C++ helper injected into the running REPL session (interpreted, no compilation).
-- One entry point: rslime_rpc(id, line) prints candidates between sentinels:
--   RSLIME <id> B
--   name%K%detail      K: M method, D data, C class, V global var, F global function
--   RSLIME <id> E
-- name/K never contain '%'; detail is last so it never needs escaping.
local M = {}

M.code = [[
#include "TROOT.h"
#include "TGlobal.h"
#include "TFunction.h"
#include "TClass.h"
#include "TDataMember.h"
#include "TList.h"
#include "TCollection.h"
#include "TClassTable.h"
#include <cstdio>
#include <cstring>
#include <cctype>
#include <string>
#include <set>

static TClass* rslime_clean_class(const char* tn) {
   if (!tn || !*tn) return nullptr;
   std::string s;
   for (const char* p = tn; *p; ++p)
      if (*p != '*' && *p != '&' && *p != ' ') s += *p;
   return TClass::GetClass(s.c_str());   // triggers autoload when needed
}

static void rslime_out(const char* name, const char* kind, const char* detail) {
   // detail clamped: the answer line must stay short or the terminal wraps it
   printf("%s%%%s%%%.60s\n", name, kind, detail ? detail : "");
}

static void rslime_list_class(TClass* cl, const char* prefix) {
   if (!cl) return;
   size_t plen = prefix ? strlen(prefix) : 0;
   std::set<std::string> seen;
   const TList* ms = cl->GetListOfAllPublicMethods(true);
   if (ms) {
      TIter nm(ms);
      while (TObject* o = nm()) {
         const char* n = o->GetName();
         if (!n || seen.count(n)) continue;
         if (plen && strncmp(n, prefix, plen) != 0) continue;
         seen.insert(n);
         rslime_out(n, "M", ((TFunction*)o)->GetPrototype());
      }
   }
   const TList* ds = cl->GetListOfAllPublicDataMembers(true);
   if (ds) {
      TIter nd(ds);
      while (TObject* o = nd()) {
         const char* n = o->GetName();
         if (!n || seen.count(n)) continue;
         if (plen && strncmp(n, prefix, plen) != 0) continue;
         seen.insert(n);
         rslime_out(n, "D", ((TDataMember*)o)->GetFullTypeName());
      }
   }
}

static TClass* rslime_var_class(const char* varname) {
   TCollection* gs = (TCollection*)gROOT->GetListOfGlobals(true);
   TGlobal* g = gs ? (TGlobal*)gs->FindObject(varname) : nullptr;
   if (!g) return nullptr;
   return rslime_clean_class(g->GetTypeName());
}

// resolve a chain like  a -> b.c  (data members only; method calls are not walked).
// cells are usually indented: leading/trailing whitespace tolerated everywhere.
static TClass* rslime_head_class(const std::string& head_in) {
   size_t b = head_in.find_first_not_of(" \t");
   if (b == std::string::npos) return nullptr;
   std::string head = head_in.substr(b, head_in.find_last_not_of(" \t") - b + 1);
   size_t i = 0;
   TClass* cl = nullptr;
   bool first = true;
   while (i < head.size()) {
      while (i < head.size() && (head[i] == ' ' || head[i] == '\t')) ++i;
      std::string id;
      while (i < head.size() && (isalnum((unsigned char)head[i]) || head[i] == '_')) { id += head[i]; ++i; }
      if (id.empty()) return nullptr;
      if (first) {
         cl = rslime_var_class(id.c_str());
         first = false;
      } else {
         const TList* ds = cl ? cl->GetListOfAllPublicDataMembers(true) : nullptr;
         TDataMember* dm = ds ? (TDataMember*)ds->FindObject(id.c_str()) : nullptr;
         if (!dm) return nullptr;
         cl = rslime_clean_class(dm->GetFullTypeName());
      }
      if (!cl) return nullptr;
      while (i < head.size() && (head[i] == ' ' || head[i] == '\t')) ++i;
      if (i + 1 < head.size() && head.compare(i, 2, "->") == 0) i += 2;
      else if (i < head.size() && head[i] == '.') ++i;
      else break;
   }
   return cl;
}

void rslime_rpc(const char* id, const char* line) {
   printf("\nRSLIME %s B\n", id);
   std::string s(line ? line : "");
   while (!s.empty() && (s.back() == ' ' || s.back() == '\t')) s.pop_back();

   // trailing partial word (may be empty when the line ends with an operator)
   size_t w = s.size();
   while (w > 0 && (isalnum((unsigned char)s[w-1]) || s[w-1] == '_')) --w;
   std::string word = s.substr(w);
   std::string before = s.substr(0, w);
   while (!before.empty() && (before.back() == ' ' || before.back() == '\t')) before.pop_back();

   char op = 0;                       // '>', '.', ':' or none
   std::string head;
   if (s.size() >= 2 && s.compare(s.size()-2, 2, "->") == 0) { op = '>'; head = s.substr(0, s.size()-2); word.clear(); }
   else if (s.size() >= 2 && s.compare(s.size()-2, 2, "::") == 0) { op = ':'; head = s.substr(0, s.size()-2); word.clear(); }
   else if (!s.empty() && s[s.size()-1] == '.') { op = '.'; head = s.substr(0, s.size()-1); word.clear(); }
   else if (before.size() >= 2 && before.compare(before.size()-2, 2, "->") == 0) { op = '>'; head = before.substr(0, before.size()-2); }
   else if (before.size() >= 2 && before.compare(before.size()-2, 2, "::") == 0) { op = ':'; head = before.substr(0, before.size()-2); }
   else if (!before.empty() && before[before.size()-1] == '.') { op = '.'; head = before.substr(0, before.size()-1); }

   if (op) {
      size_t hb = head.find_first_not_of(" \t");
      if (hb == std::string::npos) head.clear();
      else head = head.substr(hb, head.find_last_not_of(" \t") - hb + 1);
      TClass* cl = (op == ':') ? TClass::GetClass(head.c_str())
                               : rslime_head_class(head);
      rslime_list_class(cl, word.c_str());
   } else if (!word.empty() && (isalpha((unsigned char)word[0]) || word[0] == '_')) {
      std::set<std::string> seen;
      TCollection* gs = (TCollection*)gROOT->GetListOfGlobals(true);
      if (gs) {
         TIter ng(gs);
         while (TObject* o = ng()) {
            const char* n = o->GetName();
            if (n && !strchr(n, ' ') && strncmp(n, word.c_str(), word.size()) == 0)
               { seen.insert(n); rslime_out(n, "V", ((TGlobal*)o)->GetTypeName()); }
         }
      }
      TCollection* fs = (TCollection*)gROOT->GetListOfGlobalFunctions(true);
      if (fs) {
         TIter nf(fs);
         while (TObject* o = nf()) {
            const char* n = o->GetName();
            if (n && !strchr(n, ' ') && strncmp(n, word.c_str(), word.size()) == 0 && !seen.count(n))
               { seen.insert(n); rslime_out(n, "F", ((TFunction*)o)->GetPrototype()); }
         }
      }
      TCollection* lc = (TCollection*)gROOT->GetListOfClasses();
      if (lc) {
         TIter ncl(lc);
         while (TObject* o = ncl()) {
            const char* n = o->GetName();
            if (n && !strchr(n, ' ') && strncmp(n, word.c_str(), word.size()) == 0 && !seen.count(n))
               { seen.insert(n); rslime_out(n, "C", "class"); }
         }
      }
      TClassTable::Init();
      const char* cn;
      while ((cn = TClassTable::Next()))
         if (!strchr(cn, ' ') && strncmp(cn, word.c_str(), word.size()) == 0 && !seen.count(cn))
            { seen.insert(cn); rslime_out(cn, "C", "class"); }
   }
   printf("RSLIME %s E\n", id);
}

// eval sandwich markers: the expression itself is typed at the prompt
// (TInterpreter::Evaluate segfaults on bad input; the prompt never does)
void rslime_mark(const char* id, const char* tag) {
   printf("\nRSLIME %s %s\n", id, tag);
}

// session variable panel: name%V%type
void rslime_vars(const char* id) {
   printf("\nRSLIME %s B\n", id);
   TCollection* gs = (TCollection*)gROOT->GetListOfGlobals(true);
   if (gs) {
      TIter ng(gs);
      while (TObject* o = ng()) {
         const char* n = o->GetName();
         if (n && !strchr(n, ' ')) rslime_out(n, "V", ((TGlobal*)o)->GetTypeName());
      }
   }
   printf("RSLIME %s E\n", id);
}

// signatures + docs for head.name: name%P%proto (detail = doc comment, may be empty)
void rslime_sign(const char* id, const char* line) {
   printf("\nRSLIME %s B\n", id);
   std::string s(line ? line : "");
   size_t b = s.find_first_not_of(" \t");
   if (b != std::string::npos) s = s.substr(b);
   // "obj.M(" and "obj.M" ask the same thing; drop the trailing open-paren
   while (!s.empty() && s.back() == '(') s.pop_back();

   // trailing identifier = the name being asked about
   size_t w = s.size();
   while (w > 0 && (isalnum((unsigned char)s[w-1]) || s[w-1] == '_')) --w;
   std::string name = s.substr(w);
   std::string head = s.substr(0, w);

   char op = 0;
   if (head.size() >= 2 && head.compare(head.size()-2, 2, "->") == 0) { op = '>'; head.resize(head.size()-2); }
   else if (head.size() >= 2 && head.compare(head.size()-2, 2, "::") == 0) { op = ':'; head.resize(head.size()-2); }
   else if (!head.empty() && (head.back() == '.' || head.back() == '(')) { op = '.'; head.pop_back(); }  // x.M( == x.M
   while (!head.empty() && (head.back() == ' ' || head.back() == '\t')) head.pop_back();
   if (name.empty()) { printf("RSLIME %s E\n", id); return; }

   TClass* cl = nullptr;
   if (op == ':') cl = TClass::GetClass(head.c_str());
   else if (op) cl = rslime_head_class(head);

   if (cl) {
      // methods of the resolved class/base chain
      const TList* ms = cl->GetListOfAllPublicMethods(true);
      if (ms) {
         std::set<std::string> seen;
         TIter nm(ms);
         while (TObject* o = nm()) {
            if (strcmp(o->GetName(), name.c_str()) != 0) continue;
            TFunction* f = (TFunction*)o;
            if (seen.insert(f->GetPrototype()).second)
               rslime_out(f->GetPrototype(), "P", f->GetTitle());
         }
      }
   } else if (!op) {
      // no operator: global functions first, then a class named like the word
      TCollection* fs = (TCollection*)gROOT->GetListOfGlobalFunctions(true);
      if (fs) {
         std::set<std::string> seen;
         TIter nf(fs);
         while (TObject* o = nf()) {
            if (strcmp(o->GetName(), name.c_str()) != 0) continue;
            TFunction* f = (TFunction*)o;
            if (seen.insert(f->GetPrototype()).second)
               rslime_out(f->GetPrototype(), "P", f->GetTitle());
         }
      }
      TClass* k = TClass::GetClass(name.c_str());
      if (k) rslime_out(k->GetName(), "C", k->GetTitle());
   }
   printf("RSLIME %s E\n", id);
}
]]

return M
