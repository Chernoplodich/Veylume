# Third-party notices

Veylume's own code is distributed under the MIT license. The following components keep their original licenses and copyright notices. Their license texts are included in the app's resource bundle and in [Acknowledgements](Veylume/Kit/Resources/Acknowledgements).

| Component | License | Source |
|---|---|---|
| FluidAudio | Apache-2.0 | [FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio) |
| WhisperKit / Argmax OSS | MIT, with Apache-2.0 notices for derived components | [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) |
| Sparkle | MIT | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) |
| Swift Argument Parser | Apache-2.0 | [apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) |
| NeMo text processing / text-processing-rs | Apache-2.0 and its documented transitive licenses | [FluidInference/text-processing-rs](https://github.com/FluidInference/text-processing-rs) |
| fastcluster | BSD-2-Clause | Included by FluidAudio; see its bundled notice |

Dependency revisions are pinned in `Package.resolved`. Notices supplied by FluidAudio and Argmax are preserved, including those for their embedded components.

## Speech models

Model weights are downloaded separately, not included in the installer or source repository. They keep their own licenses; the application's MIT license does not relicense them. Each manifest pins its revision, source, license URL, and file hashes.

| Model | License | Attribution and terms |
|---|---|---|
| Cohere Transcribe | apache-2.0 | [Model card](https://huggingface.co/FluidInference/cohere-transcribe-03-2026-coreml/blob/e1ce10d4cae2ca9a8b36cef5786fa3660f070050/README.md) |
| Whisper Small | mit | [Model card](https://huggingface.co/argmaxinc/whisperkit-coreml/blob/0f63a7800b00dd0226abd051b906c246e1907482/README.md) |
| Whisper Large v3 | mit | [Model card](https://huggingface.co/argmaxinc/whisperkit-coreml/blob/0f63a7800b00dd0226abd051b906c246e1907482/README.md) |
| Parakeet TDT V3 | cc-by-4.0 | [Model card](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/blob/7dd20fe6b1797d35f5e3307e8b1732d9a178edfe/README.md) |
| Whisper Large v3 Turbo | mit | [Model card](https://huggingface.co/argmaxinc/whisperkit-coreml/blob/0f63a7800b00dd0226abd051b906c246e1907482/README.md) |

Parakeet is a model from NVIDIA; the Core ML conversion is provided by FluidInference. Whisper originates from OpenAI and is used through WhisperKit. Cohere Transcribe originates from Cohere and is used through the local FluidAudio adapter. Provider names identify the underlying projects; they do not imply endorsement of Veylume.

## По-русски

MIT относится к собственному коду Veylume. Сторонние библиотеки сохраняют свои лицензии и уведомления об авторстве; полные тексты включены в ресурсы приложения. Веса моделей скачиваются отдельно и распространяются по своим условиям из таблицы. Указание разработчика модели не означает, что он одобряет или поддерживает Veylume.
