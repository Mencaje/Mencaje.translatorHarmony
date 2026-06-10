// node scripts/gen_mymemory_codes.js
const fs = require('fs');
const path = require('path');

const j = require('../entry/src/main/resources/rawfile/flores200_languages.json');

/** FLORES 3-letter prefix → ISO 639-1 / RFC3066 for MyMemory langpair */
const FLORES_TO_ISO6391 = {
  ace: 'ace',
  acm: 'ar',
  acq: 'ar',
  aeb: 'ar',
  afr: 'af',
  ajp: 'ar',
  aka: 'ak',
  als: 'sq',
  amh: 'am',
  apc: 'ar',
  ars: 'ar',
  ary: 'ar',
  arz: 'ar',
  asm: 'as',
  ast: 'ast',
  awa: 'hi',
  ayr: 'ay',
  azj: 'az',
  bak: 'ba',
  bam: 'bm',
  bel: 'be',
  ben: 'bn',
  bho: 'hi',
  bod: 'bo',
  bos: 'bs',
  bul: 'bg',
  cat: 'ca',
  ceb: 'ceb',
  ces: 'cs',
  cym: 'cy',
  dan: 'da',
  ell: 'el',
  epo: 'eo',
  est: 'et',
  eus: 'eu',
  fin: 'fi',
  gle: 'ga',
  glg: 'gl',
  guj: 'gu',
  hau: 'ha',
  heb: 'he',
  hrv: 'hr',
  hun: 'hu',
  hye: 'hy',
  ibo: 'ig',
  isl: 'is',
  jav: 'jv',
  kat: 'ka',
  kaz: 'kk',
  khk: 'mn',
  khm: 'km',
  kin: 'rw',
  kir: 'ky',
  lao: 'lo',
  lit: 'lt',
  ltz: 'lb',
  lvs: 'lv',
  mal: 'ml',
  mar: 'mr',
  mkd: 'mk',
  mri: 'mi',
  mya: 'my',
  nob: 'no',
  npi: 'ne',
  nya: 'ny',
  ory: 'or',
  pan: 'pa',
  pes: 'fa',
  plt: 'mg',
  ron: 'ro',
  san: 'sa',
  sin: 'si',
  slk: 'sk',
  slv: 'sl',
  sna: 'sn',
  som: 'so',
  srp: 'sr',
  sun: 'su',
  swe: 'sv',
  swh: 'sw',
  tam: 'ta',
  tel: 'te',
  tgk: 'tg',
  tgl: 'tl',
  urd: 'ur',
  uzn: 'uz',
  wol: 'wo',
  xho: 'xh',
  yor: 'yo',
  yue: 'zh-TW',
  zsm: 'ms',
  zul: 'zu',
};

const SPECIAL = { zh: 'zh-CN', 'zh-Hant': 'zh-TW' };
const out = {};
for (const row of j) {
  const iso = row.isoCode;
  if (SPECIAL[iso]) {
    out[iso] = SPECIAL[iso];
  } else if (iso.length === 2) {
    out[iso] = iso;
  } else if (FLORES_TO_ISO6391[iso]) {
    out[iso] = FLORES_TO_ISO6391[iso];
  } else {
    out[iso] = iso;
  }
}

const lines = Object.keys(out)
  .sort()
  .map((k) => `    '${k}': '${out[k]}',`);

const body = `/**
 * FLORES/NLLB 内部 isoCode → MyMemory langpair 码（ISO 639-1 或 RFC3066）。
 * 由 scripts/gen_mymemory_codes.js 根据 flores200_languages.json 生成，勿手改 MAP。
 */
export class MyMemoryLanguageCodes {
  private static readonly MAP: Record<string, string> = {
${lines.join('\n')}
  };

  static toMyMemoryCode(iso: string): string {
    const key = iso.trim();
    if (key.length === 0) {
      return 'en';
    }
    const hit = MyMemoryLanguageCodes.MAP[key];
    if (hit !== undefined && hit.length > 0) {
      return hit;
    }
    if (key.length === 2) {
      return key.toLowerCase();
    }
    return key.toLowerCase();
  }
}
`;

const dest = path.join(__dirname, '../entry/src/main/ets/translation/MyMemoryLanguageCodes.ets');
fs.writeFileSync(dest, body);
console.log('Wrote', Object.keys(out).length, 'entries to', dest);
