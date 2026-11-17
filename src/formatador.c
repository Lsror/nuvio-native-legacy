// Ver formatador.h.
#include "formatador.h"
#include "limpa.h"
#include <stdio.h>
#include <string.h>

typedef struct { const char *utf8, *padrao, *minimalista; int cor; } Icone;
static const Icone TAB[] = {
#include "formatador_icones.inc"
};
#define N_TAB ((int)(sizeof TAB / sizeof *TAB))

int formatador_icones_n(void) { return N_TAB; }

// Mesmo decodificador estrito de limpa.c: sequencia invalida = U+FFFD, 1 byte.
static unsigned long dec(const unsigned char *p, int *n) {
  unsigned long cp;
  int len, i;
  if (*p < 0x80) { *n = 1; return *p; }
  if (*p >= 0xC2 && *p <= 0xDF) { len = 2; cp = *p & 0x1F; }
  else if (*p >= 0xE0 && *p <= 0xEF) { len = 3; cp = *p & 0x0F; }
  else if (*p >= 0xF0 && *p <= 0xF4) { len = 4; cp = *p & 0x07; }
  else { *n = 1; return 0xFFFD; }
  for (i = 1; i < len; i++) {
    if ((p[i] & 0xC0) != 0x80) { *n = 1; return 0xFFFD; }
    cp = cp << 6 | (p[i] & 0x3F);
  }
  if ((len == 3 && cp < 0x800) || (len == 4 && (cp < 0x10000 || cp > 0x10FFFF)) ||
      (cp >= 0xD800 && cp <= 0xDFFF)) { *n = 1; return 0xFFFD; }
  *n = len;
  return cp;
}
static int ehVS(unsigned long c) { return c == 0xFE0F || c == 0xFE0E; }
static int ehTom(unsigned long c) { return c >= 0x1F3FB && c <= 0x1F3FF; }

// Depois do icone: seletor de variacao, tom de pele e o resto de uma sequencia
// ZWJ desconhecida (ZWJ + pictograma) vao junto. Sem isso "🕵️‍♀️" deixava um
// "♀" solto, que nv_limpar_texto transforma em " · ".
static const unsigned char *cauda(const unsigned char *q) {
  for (;;) {
    int n, n2;
    unsigned long c;
    if (!*q) return q;
    c = dec(q, &n);
    if (ehVS(c) || ehTom(c)) { q += n; continue; }
    if (c == 0x200D && q[n]) {
      unsigned long c2 = dec(q + n, &n2);
      if (c2 >= 0x2000 && c2 != 0xFFFD) { q += n + n2; continue; }
    }
    return q;
  }
}

int formatador_icone_em(const char *p, size_t *len) {
  const unsigned char *s = (const unsigned char *)p;
  if (!s || *s < 0xC2) return -1;
  for (int k = 0; k < N_TAB; k++) {
    const unsigned char *e = (const unsigned char *)TAB[k].utf8, *q = s;
    int ok = 1;
    if (*e != *s) continue;
    while (*e) {
      int ne, nq = 1;
      unsigned long ce = dec(e, &ne), cq = 0;
      for (;;) {
        if (!*q) { ok = 0; break; }
        cq = dec(q, &nq);
        // O texto pode trazer VS16/VS15 e tom de pele onde a tabela nao tem.
        if (ehVS(cq) || (ehTom(cq) && !ehTom(ce))) { q += nq; continue; }
        break;
      }
      if (!ok || cq != ce) { ok = 0; break; }
      e += ne; q += nq;
    }
    if (!ok) continue;
    q = cauda(q);
    if (len) *len = (size_t)(q - s);
    return k;
  }
  return -1;
}

const char *formatador_icone_nome(int idx, int minimalista, int *cor) {
  if (idx < 0 || idx >= N_TAB) { if (cor) *cor = 0; return NULL; }
  if (cor) *cor = minimalista ? 0 : TAB[idx].cor;
  return minimalista ? TAB[idx].minimalista : TAB[idx].padrao;
}
const char *formatador_icone_utf8(int idx) {
  return idx >= 0 && idx < N_TAB ? TAB[idx].utf8 : "";
}

// Bandeira no comeco de `s`: par de indicadores regionais ("GB") ou 🏴 com as
// etiquetas de Inglaterra, Escocia e Gales ("GB-ENG"). 0 = nao e bandeira.
static size_t bandeiraEm(const unsigned char *s, char cc[8]) {
  int n1, n2;
  unsigned long a = dec(s, &n1), b;
  if (a >= 0x1F1E6 && a <= 0x1F1FF && s[n1]) {
    b = dec(s + n1, &n2);
    if (b >= 0x1F1E6 && b <= 0x1F1FF) {
      cc[0] = (char)('A' + (a - 0x1F1E6)); cc[1] = (char)('A' + (b - 0x1F1E6)); cc[2] = 0;
      return (size_t)(n1 + n2);
    }
    return 0;
  }
  if (a == 0x1F3F4) {
    static const struct { const char *tag, *cc; } SUB[] = {
      { "gbeng", "GB-ENG" }, { "gbsct", "GB-SCT" }, { "gbwls", "GB-WLS" } };
    char tag[8];
    int t = 0;
    const unsigned char *q = s + n1;
    for (;;) {
      int n;
      unsigned long c;
      if (!*q) return 0;
      c = dec(q, &n);
      if (c == 0xE007F) { q += n; break; }
      if (c < 0xE0020 || c > 0xE007E || t >= 7) return 0;
      tag[t++] = (char)(c - 0xE0000);
      q += n;
    }
    tag[t] = 0;
    for (unsigned i = 0; i < sizeof SUB / sizeof *SUB; i++)
      if (!strcmp(tag, SUB[i].tag)) { strcpy(cc, SUB[i].cc); return (size_t)(q - s); }
  }
  return 0;
}

static int poe(char *out, size_t cap, size_t *k, const char *rec, size_t n) {
  if (*k + n + 1 > cap) return 0;
  memcpy(out + *k, rec, n);
  *k += n;
  out[*k] = 0;
  return 1;
}

// Texto entre dois icones -> uma peca 'T' limpa (ou nada, se so tinha enfeite).
static int texto(const char *ini, size_t n, char *out, size_t cap, size_t *k) {
  char cru[2048], limpo[2048];
  if (!n) return 1;
  if (n >= sizeof cru) n = sizeof cru - 1;
  memcpy(cru, ini, n); cru[n] = 0;
  nv_limpar_texto(cru, limpo, sizeof limpo, NV_LIMPA_UMA_LINHA);
  nv_aparar_separadores(limpo);
  if (!limpo[0]) return 1;
  {
    size_t l = strlen(limpo);
    if (*k + l + 3 > cap) return -1;
    out[(*k)++] = 'T';
    memcpy(out + *k, limpo, l + 1);
    *k += l + 1;
    out[*k] = 0;
  }
  return 2;
}

int formatador_pecas(const char *in, size_t n, char *out, size_t cap, size_t *k,
                     int (*bandeira_existe)(const char *cc)) {
  char linha[4096];
  size_t i = 0, seg = 0;
  int pecas = 0, r;
  if (!in || !out || !k || *k >= cap) return 0;
  if (n >= sizeof linha) n = sizeof linha - 1;
  memcpy(linha, in, n); linha[n] = 0;
  while (i < n) {
    size_t len = 0;
    char cc[8], rec[16];
    int ic = (unsigned char)linha[i] >= 0xC2 ? formatador_icone_em(linha + i, &len) : -1;
    size_t lb = ic < 0 && (unsigned char)linha[i] == 0xF0 ? bandeiraEm((const unsigned char *)linha + i, cc) : 0;
    if (lb && bandeira_existe && !bandeira_existe(cc)) lb = 0;
    if (ic >= 0 || lb) {
      if ((r = texto(linha + seg, i - seg, out, cap, k)) < 0) return pecas;
      pecas += r == 2;
      if (ic >= 0) { snprintf(rec, sizeof rec, "I%03d", ic); if (!poe(out, cap, k, rec, 4)) return pecas; }
      else {
        size_t l = (size_t)snprintf(rec, sizeof rec, "B%s", cc);
        if (!poe(out, cap, k, rec, l + 1)) return pecas;   // +1: leva o '\0'
        i += lb;
        // VS16 colado na bandeira (raro, mas acontece em copia de texto).
        while (i < n) { int m; unsigned long c = dec((const unsigned char *)linha + i, &m); if (!ehVS(c)) break; i += (size_t)m; }
        seg = i; pecas++;
        continue;
      }
      pecas++;
      i += len; seg = i;
      continue;
    }
    { int m; dec((const unsigned char *)linha + i, &m); i += (size_t)m; }
  }
  if ((r = texto(linha + seg, i - seg, out, cap, k)) == 2) pecas++;
  return pecas;
}
