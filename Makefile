PKG        := --package-path AntiFishCore
MODELS_DIR := AntiFish/Resources/Models
SILERO_URL := https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx
SILERO_SHA := 9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6
SPK_URL    := https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/wespeaker_en_voxceleb_resnet34_LM.onnx
SPK_SHA    := e9848563da86f263117134dfd7ad63c92355b37de492b55e325400c9d9c39012
export ANTIFISH_MODELS_DIR := $(CURDIR)/$(MODELS_DIR)

.PHONY: models build test test-integration cli clean

models: $(MODELS_DIR)/silero_vad.onnx $(MODELS_DIR)/wespeaker_en_voxceleb_resnet34_LM.onnx

$(MODELS_DIR)/silero_vad.onnx:
	mkdir -p $(MODELS_DIR)
	curl -L --fail --progress-bar -o $@ $(SILERO_URL)
	echo "$(SILERO_SHA)  $@" | shasum -a 256 -c -

$(MODELS_DIR)/wespeaker_en_voxceleb_resnet34_LM.onnx:
	mkdir -p $(MODELS_DIR)
	curl -L --fail --progress-bar -o $@ $(SPK_URL)
	echo "$(SPK_SHA)  $@" | shasum -a 256 -c -

build:
	swift build $(PKG)

# Unit tests: no WhatsApp data. Model-dependent unit tests skip themselves when models are absent.
test:
	swift test $(PKG) --skip IntegrationTests

# Integration tests: read this machine's live WhatsApp container. Nothing is written to the repo.
test-integration: models
	ANTIFISH_REAL_WA=1 swift test $(PKG) --filter IntegrationTests

cli: models
	swift run $(PKG) antifish $(ARGS)

clean:
	rm -rf AntiFishCore/.build
