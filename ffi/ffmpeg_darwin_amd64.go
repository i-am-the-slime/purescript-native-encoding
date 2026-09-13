//go:build darwin && amd64

package native_encoding

import _ "embed"

//go:embed bin/ffmpeg_darwin_amd64
var ffmpegBinary []byte

func getFfmpeg() ([]byte, string) { return ffmpegBinary, "ffmpeg" }
