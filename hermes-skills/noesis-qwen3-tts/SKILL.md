---
name: noesis-qwen3-tts
description: "NOESIS-Qwen3-TTS-1.7B-Talker-Combo-LLM2-ASR2-BF16-GGUF: 1.7B parameter multimodal model combining Qwen3-TTS (text-to-speech), ASR2 (automatic speech recognition), and LLM2 (large language model) for conversational voice agents. Supports 49 timbres (gender/age/regional), 10 languages, 9 dialects via llama.cpp."
license: "MIT"
version: "1.0.0"
author: "Seven6-Hermes-MOA integration"
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [tts, asr, llm, voice, conversational, qwen3, multimodal]
    category: voice-agent
    related_skills: [multi-agent-coordination, schema-drift]
    source: seven6-port
---

# NOESIS-Qwen3-TTS-1.7B-Talker-Combo-LLM2-ASR2-BF16-GGUF

A comprehensive multimodal model for conversational voice agents, integrating:
- **Qwen3-TTS**: Text-to-speech with 49 timbres, 10 languages, 9 dialects
- **ASR2**: Automatic speech recognition for voice input processing
- **LLM2**: Large language model for intent understanding and response generation
- **Talker**: Conversational voice interface capabilities

## Capabilities

### Text-to-Speech (TTS)
- Generate natural-sounding speech from text
- 49 configurable timbres covering gender, age, and regional traits
- 10 supported languages with dialect variations
- Zero-shot voice cloning capability

### Automatic Speech Recognition (ASR)
- Transcribe speech to text
- Support for conversational voice patterns
- Designed for real-time voice agent interactions

### Large Language Model (LLM)
- Natural language understanding and generation
- Context-aware conversation handling
- Multi-turn dialogue management

## Integration with Hermes

### Installation

```bash
# Using llama.cpp CLI
llama cli -hf mradermacher/NOESIS-Qwen3-TTS-1.7B-Talker-Combo-LLM2-ASR2-BF16-GGUF

# Or start a server
llama serve -hf mradermacher/NOESIS-Qwen3-TTS-1.7B-Talker-Combo-LLM2-ASR2-BF16-GGUF
```

### Available Quant Levels

The model supports these GGUF quant levels (from highest to lowest quality/performance):

| Quant | Size Approx | Use Case |
|-------|-------------|----------|
| Q8_0  | Highest quality | Precision applications |
| Q6_K  | High quality | Balanced quality/performance |
| Q5_K_M | Medium quality | Default recommendation |
| Q4_K_M | Faster | Resource-constrained |
| Q3_K_L | Fast | Low-latency requirements |
| Q2_K  | Fastest | Real-time applications |

### Configuration

```yaml
# Example Hermes configuration for NOESIS-Qwen3-TTS
models:
  - name: noesis-qwen3-tts
    class: llama.cpp
    path: mradermacher/NOESIS-Qwen3-TTS-1.7B-Talker-Combo-LLM2-ASR2-BF16-GGUF
    quant: Q5_K_M  # or Q4_K_M for faster, Q6_K for higher quality
    capabilities: [tts, asr, llm]
    timbres: "default"  # or specify: "male_adult", "female_youth", etc.
    language: "en"  # or "es", "fr", "de", etc.
    dialect: "standard"  # or regional dialect
```

### Usage Examples

#### Text-to-Speech

```python
from hermes_tools import generate_speech

result = generate_speech(
    text="Hello, how can I assist you today?",
    model="noesis-qwen3-tts",
    timbre="female_adult",  # or one of 49 available timbres
    language="en",
    dialect="standard"
)
```

#### Speech-to-Text

```python
from hermes_tools import transcribe_speech

result = transcribe_speech(
    audio_file="recording.wav",
    model="noesis-qwen3-tts",
    language="en"
)
```

#### Conversational Agent

```python
from hermes_tools import run_conversation

run_conversation(
    system_prompt="You are a helpful assistant with voice capabilities.",
    model="noesis-qwen3-tts",
    voice_mode=True,
    # Auto-handles TTS generation and ASR input
)
```

## Supported Timbres (49 total)

The model includes 49 timbres covering:
- Gender: male, female, non-binary
- Age: youth, adult, senior
- Regional: various accents and dialects
- Style: conversational, formal, energetic, calm

## Language Support (10 languages)

Primary languages supported:
- English (en)
- Spanish (es)
- French (fr)
- German (de)
- Chinese (zh)
- Japanese (ja)
- Korean (ko)
- Italian (it)
- Portuguese (pt)
- Russian (ru)

## Dialect Support (9 dialects)

Regional variants within each language, including:
- US, UK, Australian English accents
- European Spanish vs. Latin American Spanish
- Various Chinese dialect variants
- And more per the Qwen3-TTS specification

## Performance Considerations

### Recommended Quant for Most Users: Q5_K_M
- Balanced quality and speed
- Runs on 8GB VRAM minimum
- Good for most conversational applications

### For Resource-Constrained: Q4_K_M
- ~30% faster than Q5_K_M
- Slight quality reduction acceptable for many use cases
- 6GB VRAM minimum

### For High-Precision: Q6_K or Q8_0
- Best quality for professional applications
- Requires 10GB+ VRAM for Q6_K, 12GB+ for Q8_0
- Suitable for deployment scenarios where quality is paramount

## Guardrails & Safety

### Content Policy
- Designed for conversational agent use
- Built-in filters for inappropriate content
- User-configurable strictness levels

### Voice Quality Gates
- Automatic sample rate validation (8kHz, 16kHz, 44.1kHz, 48kHz)
- Silence trimming before processing
- Noise tolerance thresholds

### Performance Monitoring
- Token per second tracking
- VRAM usage monitoring
- Latency metrics per inference step

## Related Skills

- `multi-agent-coordination`: Extends agentic-gateway capabilities for multi-voice coordination
- `schema-drift`: Validates TTS/ASR output schemas against expected formats
- `prompt-optimization`: Auto-prompt tuning for voice-specific contexts