package main

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"
)

func render(root, fragments, prompt string) (string, error) {
	t := template.New("prompt").Option("missingkey=zero").Funcs(template.FuncMap{
		"cmd": func(...string) string { return "gc" },
	})
	for _, directory := range []string{fragments, filepath.Join(root, "firstmate", "template-fragments")} {
		files, err := filepath.Glob(filepath.Join(directory, "*.template.md"))
		if err != nil {
			return "", err
		}
		for _, file := range files {
			contents, err := os.ReadFile(file)
			if err != nil {
				return "", err
			}
			if _, err := t.Parse(string(contents)); err != nil {
				return "", err
			}
		}
	}
	contents, err := os.ReadFile(filepath.Join(root, "firstmate", "assets", "prompts", prompt))
	if err != nil {
		return "", err
	}
	if _, err := t.Parse(string(contents)); err != nil {
		return "", err
	}
	var output bytes.Buffer
	if err := t.Execute(&output, map[string]string{"BindingName": "firstmate", "RigName": "demo", "DefaultBranch": "main"}); err != nil {
		return "", err
	}
	return output.String(), nil
}

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: render-prompts ROOT GASTOWN_FRAGMENTS")
		os.Exit(2)
	}
	mayor, err := render(os.Args[1], os.Args[2], "mayor.template.md")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	refinery, err := render(os.Args[1], os.Args[2], "refinery.template.md")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if !strings.Contains(mayor, "the captain is the sole merge owner") {
		fmt.Fprintln(os.Stderr, "rendered Mayor prompt omits captain-only merge ownership")
		os.Exit(1)
	}
	if !strings.Contains(refinery, "unless a resolved `merge` decision exists for that exact change") || !strings.Contains(refinery, "captain's recorded answer") {
		fmt.Fprintln(os.Stderr, "rendered refinery prompt omits the ledger gate")
		os.Exit(1)
	}
}
