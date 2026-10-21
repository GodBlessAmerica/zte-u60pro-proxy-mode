package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestGeneratedConfigWithSingBox(t *testing.T) {
	sb := os.Getenv("U60_SING_BOX")
	if sb == "" {
		t.Skip("set U60_SING_BOX for real sing-box schema validation")
	}
	b, err := os.ReadFile("../../configs/mode5-ssh.example.json")
	if err != nil {
		t.Fatal(err)
	}
	var c map[string]any
	json.Unmarshal(b, &c)
	o := c["outbounds"].([]any)[0].(map[string]any)
	o["server"] = "127.0.0.1"
	o["user"] = "test"
	delete(o, "private_key_path")
	o["password"] = "test-placeholder"
	b, _ = json.Marshal(c)
	b, _, err = sshIPv6Config(b)
	if err != nil {
		t.Fatal(err)
	}
	f := filepath.Join(t.TempDir(), "runtime.json")
	os.WriteFile(f, b, 0600)
	if out, err := exec.Command(sb, "check", "-c", f).CombinedOutput(); err != nil {
		t.Fatalf("%v: %s", err, out)
	}
}
