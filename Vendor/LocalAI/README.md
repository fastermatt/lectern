# Optional local inference runtime

Pinned upstream: https://github.com/ggml-org/llama.cpp/releases/tag/b11968
Official artifact: llama-b11968-bin-macos-arm64.tar.gz
Archive SHA-256: 74b7034262407e60acdc507508f260ba50fcba0cdf6a42fe74b21fb8b5088fa6

The server and dylibs are copied from that upstream artifact, preserving dylib symlinks.
LICENSE is the upstream MIT license. provenance.json records the original, pre-signing
file hashes. package-app.sh verifies these hashes, compiles scripts/local-ai-runner.c,
and signs the runtime in the finished application. Signing changes Mach-O hashes.
The runner is Lectern source, not an upstream binary. Only the server and libraries
are distributed; unrelated upstream CLI tools are not required.

Model weights are not bundled. LocalAIModels.swift lists exact source revisions,
filenames, sizes and SHA-256 hashes. Changes to the engine or models require new
real download/start/chat/stop/restart tests on Apple Silicon, a provenance review,
and a new app release. Never replace a model at a floating URL or accept a hash
provided only by the just-downloaded file. Offline study remains independent.
