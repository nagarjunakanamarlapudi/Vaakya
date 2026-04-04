# Vaakya Competitive Landscape

**Date:** March 2026
**Product:** Vaakya — macOS/iOS local-first AI meeting notepad
**Primary competitor:** Granola.ai

---

## 1. Direct Competitor: Granola.ai

The elephant in the room. Granola just raised $125M at a $1.5B valuation (March 2026, led by Index Ventures). Total raised: $192M. Jumped from $250M valuation in under a year.

| Attribute | Granola | Vaakya (planned) |
|---|---|---|
| **Pricing** | Free (limited) / $14/user/mo Business / $35/user/mo Enterprise | Free local / ~$14/mo paid cloud |
| **Platforms** | Mac + Windows (recently added) | Mac + iOS |
| **Transcription** | Cloud-based (system audio capture) | Local MLX Whisper (on-device) |
| **Speaker ID** | No | Yes (pyannote/ONNX) |
| **Audio playback** | No | Yes (synced to transcript) |
| **Offline mode** | No (requires internet for AI) | Yes (fully functional offline) |
| **AI models** | GPT-4o + Claude (cloud only) | Hybrid: local Ollama or cloud (BYOK) |
| **Bot-free** | Yes (captures system audio) | Yes (captures system audio) |
| **Privacy** | Audio processed in cloud; SOC 2 Type 2 | Transcription never leaves device |
| **Enterprise features** | Spaces, personal API, enterprise API, MCP server | Planned: sync, share links, team Spaces |
| **Indic languages** | No specific support | Opportunity for differentiation |

**Granola's trajectory:** Moving from prosumer notepad to enterprise AI platform. Launching agent features (automated tasks from meeting context) within a year. This is the competitive moat Vaakya must either match or intentionally avoid.

**Granola's weaknesses** (from user reports):
- Messed up numbers in transcripts
- No speaker memory/identification
- Requires Google account to sign up (excludes Microsoft/Apple-only orgs)
- Mac-only until recently; Windows still newer
- No offline capability
- All data goes to OpenAI/Anthropic with no opt-out on free tier

---

## 2. Global Competitors with India Presence

### Tier 1: Cloud-First Meeting Bots (Enterprise)

#### Fireflies.ai
- **India connection:** Indian-origin unicorn ($1B valuation, June 2025). 20-30% employees in India. India = 10-15% of revenue, growing fast. CEO Krish Ramineni says "India is on the verge of breaking big."
- **Pricing:** Free / Pro $10/mo / Business $19/mo / Enterprise $39/mo (all USD)
- **Languages:** 100+ globally, 14+ Indian regional languages including Hindi, Tamil, Telugu
- **Model:** Cloud meeting bot joins calls; processes 2B+ meeting minutes to date
- **Strength:** Deep enterprise integrations, CRM sync, conversation intelligence
- **Weakness vs Vaakya:** Sends a bot to meetings (visible to all), cloud-only processing, no offline, no audio playback sync
- **Threat level:** HIGH in India enterprise market

#### Otter.ai
- **India presence:** Used widely by Indian tech workers
- **Pricing:** Free / Pro $8.33/mo / Business $20/mo
- **Languages:** English, Japanese, Spanish, French only. NO Hindi/Tamil/Telugu support
- **Weakness:** Very limited language support rules it out for Indic-language use cases
- **Threat level:** MEDIUM (English-only meetings in India)

#### tl;dv
- **Pricing:** Free / Pro $18/mo / Business $59/mo
- **Languages:** Supports Hindi among 30+ languages
- **Model:** Meeting bot joins calls
- **Threat level:** LOW-MEDIUM in India

### Tier 2: Bot-Free Notepad Competitors (Direct Granola Alternatives)

#### Jamie (meetjamie.ai)
- **Pricing:** Free (10 meetings/mo) / Plus EUR 25/mo / Pro EUR 47/mo / Team EUR 39/user/mo
- **Platforms:** Mac, Windows, iOS
- **Key features:** Bot-free (captures system audio), offline recording, 90+ languages, speaker ID, CRM integrations (HubSpot, Salesforce, Attio)
- **Privacy:** GDPR-compliant, servers in Frankfurt, audio deleted after transcript generation
- **Weakness vs Vaakya:** Cloud processing (not local), no audio playback sync, expensive
- **Threat level:** HIGH (most feature-complete Granola alternative)

#### Krisp
- **Pricing:** Free (limited) / Core $8/mo / Advanced $15/mo / Enterprise custom
- **Key features:** AI noise cancellation (unique differentiator), bot-free, speaker ID, on-device audio processing, accent conversion
- **Privacy:** SOC 2, HIPAA, GDPR, PCI-DSS certified
- **Platforms:** Mac, Windows, iOS, Android
- **Languages:** Not specified for Indic languages
- **Weakness vs Vaakya:** Noise cancellation is core (meeting notes secondary), no audio playback
- **Threat level:** MEDIUM-HIGH (strong privacy story, but different positioning)

#### Talat (talat.app) -- NEW, March 2026
- **Featured in TechCrunch** (March 24, 2026)
- **Pricing:** $49 pre-release / $99 at 1.0 (one-time purchase, no subscription)
- **Platforms:** Mac only (M-series required)
- **Key features:** 100% local processing, uses Qwen3-4B for summarization on Apple Neural Engine, configurable LLM choice, auto-export to Obsidian, webhooks, MCP server
- **Privacy:** Audio never leaves Mac, no cloud dependency
- **Weakness vs Vaakya:** Solo developer (Nick Payne), no speaker ID, no iOS, very early stage
- **Threat level:** MEDIUM (closest philosophical competitor -- same local-first vision)

### Tier 3: Open Source / Privacy-First

#### Char (char.com, formerly Hyprnote)
- **Pricing:** Free, open source
- **Platforms:** Mac (primary)
- **Key features:** Local-first, filesystem-based (like Obsidian), BYOK or on-device AI, plain markdown files, zero lock-in
- **Weakness:** Less mature, no mobile, no live AI chat, community-driven pace
- **Threat level:** LOW (different audience -- developer/hacker types)

#### Meetily / OpenGranola
- **Pricing:** Free, open source
- **Key features:** 100% local processing, Whisper transcription, AI summaries
- **Weakness:** Hobbyist projects, not polished products
- **Threat level:** LOW (but validates the "open/local Granola" market)

#### LocalScribe
- **Pricing:** Unknown (possibly free/beta)
- **Platforms:** macOS only
- **Key features:** Bundled Whisper + Apple Intelligence for summarization, zero network requests, source available for audit
- **Threat level:** LOW

---

## 3. India-Origin / India-Focused AI Voice & Speech Companies

These are not direct meeting-notepad competitors but represent the Indian AI speech ecosystem that Vaakya could either compete with, partner with, or build on.

### Sarvam AI (Bengaluru, founded 2023)
- **What they do:** India's leading Indic-language AI company. Builds foundational speech/language models for Indian use cases.
- **Key product:** Saaras v3 -- speech-to-text model supporting all 22 scheduled Indian languages with auto language detection, code-mixing (Hindi-English switching), and speaker diarization
- **Capabilities:** Real-time and batch transcription, diarized speech recognition for audio up to 60 minutes, handles code-mixed audio seamlessly
- **Funding:** $4M+ raised
- **Relevance to Vaakya:** Could be an alternative/complement to Whisper for Indic languages. Their Batch API with speaker diarization is directly useful for meeting transcription. Potential integration partner.

### Gnani.ai (Bengaluru, founded 2016)
- **What they do:** Voice AI infrastructure for enterprises. 14B-parameter voice-to-voice model, 30M+ voice interactions daily, 200+ enterprise clients (Tata, Air India, Hyundai, Airtel, IIFL, Bank of Baroda)
- **Languages:** 6 languages at launch (English, Hindi, Kannada, Telugu, Tamil, Gujarati), expanding to all 22
- **Funding:** $10M from Aavishkaar Capital (2026)
- **Training data:** 14M hours of India-specific audio (accents, dialects)
- **Relevance to Vaakya:** Enterprise voice AI, not consumer meeting notes. But demonstrates the Indian enterprise demand for multilingual voice AI.

### Reverie Language Technologies (Bengaluru, founded 2009)
- **What they do:** AI-powered language localization. First to launch Indian language support on Android (2011, with Qualcomm).
- **Ownership:** 83.3% acquired by Reliance Jio in 2019 for Rs 190 crore
- **Key product:** RevUp platform -- Voice API supporting 12 Indian languages (STT, TTS, Speech-to-Speech)
- **Relevance to Vaakya:** Demonstrates Jio/Reliance interest in Indian language tech. Potential partnership or competitive threat if Jio builds meeting tools.

### Emvo
- **What they do:** Launched India's first open-source secure speech-to-text model (VoiceShield) at the India AI Summit
- **Relevance to Vaakya:** Open-source STT for Indian market, security-focused

### AI4Bharat (IIT Madras)
- **What they do:** Research group building open NLP/speech resources for Indian languages
- **Key outputs:** IndicNLP catalog, ASR models for Indian languages, benchmark datasets
- **Relevance to Vaakya:** Source of fine-tuned Whisper models and training data for Indian languages

---

## 4. Other Global Players (Noteworthy)

| App | Model | Pricing | India Relevance |
|---|---|---|---|
| **Notta** | Cloud, bot-free | Free / Pro $8.25/mo | Good multilingual support |
| **Fellow** | Cloud, bot + botless | Free / Pro $7/mo | Team-focused, cross-platform |
| **read.ai** | Cloud, meeting bot | Free / Pro $19.75/mo | Enterprise intelligence |
| **Sembly AI** | Cloud | Free / Pro $10/mo | 48 languages including Hindi |
| **Hedy AI** | Cloud, bot-free | Unknown | Real-time coaching (unique angle) |
| **Votars** | Cloud, bot | Pay-as-you-go | 74+ languages, strong Hindi/Tamil/Bengali support, exports to PPT/Excel |
| **MacWhisper** | Local Whisper | One-time purchase | Privacy-focused, but transcription only (no meeting intelligence) |
| **BB Recorder** | Apple Intelligence | Unknown | On-device via Apple Neural Engine |

---

## 5. India-Specific Market Considerations

### Language Landscape
- **Code-switching is the norm.** Indian professionals routinely switch between English and Hindi/regional languages mid-sentence ("Hinglish"). Any meeting tool targeting India MUST handle code-mixed audio.
- **22 scheduled languages** under the Indian Constitution. Major business languages: English, Hindi, Tamil, Telugu, Kannada, Marathi, Bengali, Gujarati.
- **Whisper's Indian language accuracy is weak.** Tamil Large V2 achieves ~12.3% WER (87.7% accuracy). Hindi is better with fine-tuned models, but still below English. Sarvam's Saaras v3 claims state-of-the-art for Indian languages.

### Pricing Sensitivity
- Global SaaS tools price in USD, which creates sticker shock in India ($14/mo = ~Rs 1,170/mo).
- Indian SaaS companies commonly offer: generous free tiers, INR pricing, annual discounts, and team/education plans.
- One-time purchase models (like Talat at $49-99) may resonate better with Indian individual users.
- Freemium with local-only free tier (Vaakya's current plan) is well-suited for the Indian market.

### Enterprise Opportunity
- India's enterprise meeting software market is growing rapidly. Fireflies.ai reports 10-15% of revenue from India and growing.
- Indian enterprises (banking, insurance, telecom, IT services) need multilingual meeting intelligence.
- Compliance/data residency concerns are increasing -- "data stays in India" is a selling point.

### Privacy & Data Sovereignty
- India's Digital Personal Data Protection Act (DPDPA, 2023) creates awareness of data privacy.
- "Your transcription never leaves your device" is a powerful message in India, where concerns about data going to US servers are growing.
- Government and regulated industries (BFSI, healthcare) increasingly prefer on-device/on-premises solutions.

---

## 6. Competitive Positioning Map

```
                    CLOUD                          LOCAL/ON-DEVICE
                      |                                  |
ENTERPRISE   Fireflies ---- Otter ---- Krisp            |
   |         read.ai  ---- tl;dv                        |
   |         Votars   ---- Sembly                       |
   |              |                                     |
   |          Granola  ---- Jamie                    Talat
PROSUMER         |       ---- Fellow               VAAKYA (target)
   |          Notta    ---- Hedy                  Char (OSS)
   |              |                              LocalScribe
   |              |                              MacWhisper
INDIVIDUAL/       |                                     |
DEVELOPER    HappyScribe                         Meetily (OSS)
                                                 OpenGranola (OSS)
```

**Vaakya's sweet spot:** Prosumer/Individual, local/on-device, with a path to enterprise via cloud features. This is currently an underserved quadrant -- most local-first tools are hobbyist-grade, while polished products are cloud-dependent.

---

## 7. Vaakya's Competitive Advantages

1. **Local transcription (MLX Whisper):** Only a handful of polished apps do this. Granola, Jamie, Fireflies -- all cloud.
2. **Speaker identification:** Granola still lacks this. Vaakya has it from day one.
3. **Audio playback synced to transcript:** Unique among notepad-style apps. Only traditional transcription tools (Descript, etc.) offer this.
4. **Offline-first:** Most competitors require internet. Vaakya works on a flight.
5. **Privacy story:** "Your voice never leaves your Mac" -- powerful for India's DPDPA-aware market and globally.
6. **Free tier with no limits on local features:** Unlike Granola's limited free tier.
7. **BYOK / local Ollama option:** Power users choose their AI. No lock-in.

---

## 8. Vaakya's Competitive Risks

1. **Granola's momentum:** $1.5B valuation, 192M raised, rapid enterprise feature development. They could add speaker ID and offline mode.
2. **Talat's emergence:** Launched same week (March 2026), same local-first philosophy, TechCrunch coverage. First-mover risk in the "private notepad" niche.
3. **Whisper accuracy for Indian languages:** Out-of-the-box Whisper is mediocre for Hindi/Tamil. Would need fine-tuned models or Sarvam integration.
4. **No Windows support:** Granola and Jamie both support Windows. India's enterprise market is heavily Windows-based.
5. **Apple Silicon requirement:** MLX Whisper requires M-series Macs. Limits addressable market in India where Intel Macs and Windows dominate.
6. **Fireflies' India play:** They already have Indian language support, enterprise clients, and are actively investing in India.

---

## 9. Recommendations for India Market Entry

1. **Indic language support is a differentiator.** Integrate Sarvam AI's Saaras v3 as an alternative ASR engine for Hindi/Tamil/Telugu. Or ship fine-tuned Whisper models for top Indian languages.
2. **Code-switching must work.** Hindi-English ("Hinglish") is the default in Indian business meetings. Test and optimize for this.
3. **Price in INR.** Offer India-specific pricing (Rs 499/mo or Rs 4999/year for paid tier). Generous free tier is already planned and is the right call.
4. **Consider one-time purchase option.** Talat's model ($49-99 once) may resonate with Indian individual buyers who resist subscriptions.
5. **Data sovereignty messaging.** "Made in India, stays in India, processed on YOUR device" -- this message has regulatory and emotional resonance.
6. **Target Mac-using Indian professionals first.** Developers, designers, startup founders, consultants -- the segment that already uses Apple hardware and cares about privacy.
7. **Partner, don't compete, with Sarvam/Gnani.** These companies build ASR infrastructure, not consumer meeting apps. They are natural integration partners.

---

## Sources

- [Granola raises $125M, hits $1.5B valuation (TechCrunch, March 2026)](https://techcrunch.com/2026/03/25/granola-raises-125m-hits-1-5b-valuation-as-it-expands-from-meeting-notetaker-to-enterprise-ai-app/)
- [Granola Pricing](https://www.granola.ai/pricing)
- [Fireflies.ai India Strategy (Inc42)](https://inc42.com/features/fireflies-ai-unicorn-india-strategy-acquisition-enterprises/)
- [Talat AI meeting notes (TechCrunch, March 2026)](https://techcrunch.com/2026/03/24/talats-ai-meeting-notes-stay-on-your-machine-not-in-the-cloud/)
- [Sarvam AI Saaras v3](https://www.sarvam.ai/blogs/asr)
- [Sarvam Audio: Speech Recognition beyond Transcription](https://www.sarvam.ai/blogs/sarvam-audio)
- [Gnani.ai raises $10M (BusinessToday)](https://www.businesstoday.in/technology/story/gnaniai-raises-10-million-in-funding-from-aavishkaar-capital-to-scale-global-voice-ai-push-523218-2026-03-31)
- [Gnani.ai Voice AI for Indian Languages](https://www.gnani.ai/resources/blogs/voice-ai-for-indian-languages-developing-speech-models-36b9f)
- [Reverie Language Technologies](https://reverieinc.com/)
- [Krisp AI Pricing](https://krisp.ai/pricing/)
- [Jamie AI Pricing](https://www.meetjamie.ai/pricing)
- [Granola Alternatives (Jamie blog)](https://www.meetjamie.ai/blog/granola-alternatives)
- [Granola Alternatives (Krisp blog)](https://krisp.ai/blog/granola-ai-review-alternatives/)
- [Char: Open source AI notepad](https://char.com/blog/granola-ai-alternatives/)
- [Best Granola Alternatives for Private Meeting Notes (BuildBetter)](https://blog.buildbetter.ai/best-granola-alternatives-private-meeting-notes-2026/)
- [LocalScribe](https://localscribe.app/)
- [Votars Meeting Transcription for India](https://votars.ai/en/blog/5-best-meeting-transcription-tools-supporting-hindi-and-tamil-in-india/)
- [Whisper Indian Language Accuracy (arxiv)](https://arxiv.org/html/2412.19785v1)
- [AI4Bharat ASR](https://ai4bharat.iitm.ac.in/areas/asr)
- [Speaker Diarization on Apple Silicon with MLX (Medium, Feb 2026)](https://blog.ivan.digital/speaker-diarization-and-voice-activity-detection-on-apple-silicon-native-swift-with-mlx-92ea0c9aca0f)
- [WhisperKit (Argmax)](https://github.com/argmaxinc/WhisperKit)
- [Speech-Swift: ASR/TTS/Diarization toolkit for Apple Silicon](https://github.com/soniqo/speech-swift)
- [Otter.ai Supported Languages](https://help.otter.ai/hc/en-us/articles/360047247414-Supported-languages)
- [Emvo India's First Open-Source Secure STT](https://www.cxodigitalpulse.com/emvo-launches-indias-first-open-source-secure-speech-to-text-model-at-the-india-ai-summit/)
- [Top AI Notetakers 2026 (AssemblyAI)](https://www.assemblyai.com/blog/top-ai-notetakers)
- [Talat App](https://talat.app/)
