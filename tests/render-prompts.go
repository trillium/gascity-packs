package main

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"
)

func render(root, fragments, prompt, bindingName string) (string, error) {
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
	if err := t.Execute(&output, map[string]string{"BindingName": bindingName, "RigName": "demo", "DefaultBranch": "main"}); err != nil {
		return "", err
	}
	return output.String(), nil
}

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: render-prompts ROOT GASTOWN_FRAGMENTS")
		os.Exit(2)
	}
	for _, bindingName := range []string{"helm", ""} {
		mayor, err := render(os.Args[1], os.Args[2], "mayor.template.md", bindingName)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		refinery, err := render(os.Args[1], os.Args[2], "refinery.template.md", bindingName)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if !strings.Contains(mayor, "the captain is the sole merge owner") {
			fmt.Fprintln(os.Stderr, "rendered Mayor prompt omits captain-only merge ownership")
			os.Exit(1)
		}
		binding := bindingName
		if binding == "" {
			binding = "firstmate"
		}
		if !strings.Contains(mayor, "gc "+binding+" decide --binding "+binding) {
			fmt.Fprintln(os.Stderr, "rendered Mayor prompt omits its decide binding")
			os.Exit(1)
		}
		if !strings.Contains(mayor, "only `approve` authorizes that exact change to land, while `hold` leaves it unlanded") {
			fmt.Fprintln(os.Stderr, "rendered Mayor prompt omits merge outcome authority")
			os.Exit(1)
		}
		if !strings.Contains(refinery, "A script, not this prompt, decides\nwhether a change may land.") || !strings.Contains(refinery, "gc "+binding+" merge-gate land \"$WORK\" -- <the landing command>") || !strings.Contains(refinery, "hold`, keep the change unlanded and stop") {
			fmt.Fprintln(os.Stderr, "rendered refinery prompt omits the ledger gate")
			os.Exit(1)
		}
		if !strings.Contains(refinery, "Creating or publishing a PR, closing its work bead, and recording handoffs\nremain allowed") {
			fmt.Fprintln(os.Stderr, "rendered refinery prompt incorrectly gates PR publication or handoffs")
			os.Exit(1)
		}
		if strings.Count(refinery, "gc "+binding+" pr-merge-reconcile") != 3 {
			fmt.Fprintln(os.Stderr, "rendered refinery prompt omits its bound PR reconciliation commands")
			os.Exit(1)
		}
		if strings.Contains(refinery, "gc gastown pr-merge-reconcile") {
			fmt.Fprintln(os.Stderr, "rendered refinery prompt retains the gastown PR reconciliation binding")
			os.Exit(1)
		}
	}
}
