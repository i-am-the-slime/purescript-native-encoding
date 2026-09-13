package native_encoding

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"

	purs "github.com/purescript-native/go-runtime"
)

type process struct {
	command *exec.Cmd
	input   io.WriteCloser
	stderr  bytes.Buffer
	closed  bool
	waited  bool
	exit    purs.Dict
}

func check(err error) {
	if err != nil {
		panic(purs.Dict{"message": err.Error(), "stack": ""})
	}
}

func integer(value purs.Any) int {
	switch n := value.(type) {
	case int:
		return n
	case int32:
		return int(n)
	case int64:
		return int(n)
	case float64:
		return int(n)
	default:
		panic("expected an integer")
	}
}

func init() {
	exports := purs.Foreign("Native.Encoding")
	exports["byteLength"] = func(value purs.Any) purs.Any { return len(value.([]byte)) }
	exports["sha256Hex"] = func(value purs.Any) purs.Any {
		sum := sha256.Sum256(value.([]byte))
		return hex.EncodeToString(sum[:])
	}
	exports["userCacheDirectory"] = func() purs.Any {
		path, err := os.UserCacheDir()
		check(err)
		return path
	}
	exports["joinPath"] = func(parts purs.Any) purs.Any {
		values := parts.([]purs.Any)
		paths := make([]string, len(values))
		for i, value := range values {
			paths[i] = value.(string)
		}
		return filepath.Join(paths...)
	}
	exports["fileSize"] = func(path purs.Any) purs.Any {
		return func() purs.Any {
			stat, err := os.Stat(path.(string))
			if err != nil {
				return -1
			}
			return int(stat.Size())
		}
	}
	exports["makeDirectories"] = func(mode purs.Any) purs.Any {
		return func(path purs.Any) purs.Any {
			return func() purs.Any {
				check(os.MkdirAll(path.(string), os.FileMode(integer(mode))))
				return nil
			}
		}
	}
	exports["writeFile"] = func(mode purs.Any) purs.Any {
		return func(path purs.Any) purs.Any {
			return func(data purs.Any) purs.Any {
				return func() purs.Any {
					check(os.WriteFile(path.(string), data.([]byte), os.FileMode(integer(mode))))
					return nil
				}
			}
		}
	}
	exports["chmod"] = func(mode purs.Any) purs.Any {
		return func(path purs.Any) purs.Any {
			return func() purs.Any {
				check(os.Chmod(path.(string), os.FileMode(integer(mode))))
				return nil
			}
		}
	}

	processExports := purs.Foreign("Native.Encoding.Process")
	processExports["start"] = func(executable purs.Any) purs.Any {
		return func(arguments purs.Any) purs.Any {
			return func() purs.Any {
				values := arguments.([]purs.Any)
				args := make([]string, len(values))
				for i, value := range values {
					args[i] = value.(string)
				}
				p := &process{command: exec.Command(executable.(string), args...)}
				input, err := p.command.StdinPipe()
				check(err)
				p.input = input
				p.command.Stderr = &p.stderr
				if err := p.command.Start(); err != nil {
					input.Close()
					check(err)
				}
				return p
			}
		}
	}
	processExports["writeInput"] = func(handle purs.Any) purs.Any {
		return func(value purs.Any) purs.Any {
			return func() purs.Any {
				data := value.([]byte)
				n, err := handle.(*process).input.Write(data)
				check(err)
				if n != len(data) {
					check(io.ErrShortWrite)
				}
				return nil
			}
		}
	}
	processExports["closeInput"] = func(handle purs.Any) purs.Any {
		return func() purs.Any {
			p := handle.(*process)
			if !p.closed {
				p.closed = true
				check(p.input.Close())
			}
			return nil
		}
	}
	processExports["wait"] = func(handle purs.Any) purs.Any {
		return func() purs.Any {
			p := handle.(*process)
			if !p.waited {
				err := p.command.Wait()
				p.waited = true
				code := 0
				if err != nil {
					code = -1
					var exitError *exec.ExitError
					if errors.As(err, &exitError) {
						code = exitError.ExitCode()
					}
				}
				p.exit = purs.Dict{"success": err == nil, "code": code, "stderr": p.stderr.String()}
				if err != nil {
					var exitError *exec.ExitError
					if !errors.As(err, &exitError) {
						check(err)
					}
				}
			}
			return p.exit
		}
	}

	binary, name := getFfmpeg()
	purs.Foreign("Native.Encoding.FFmpeg")["executable"] = purs.Dict{"bytes": binary, "name": name}
}
