// A generated module for Cubzh functions
//
// This module has been generated via dagger init and serves as a reference to
// basic module structure as you get started with Dagger.
//
// Two functions have been pre-created. You can modify, delete, or add to them,
// as needed. They demonstrate usage of arguments and return types using simple
// echo and grep commands. The functions can be called from the dagger CLI or
// from one of the SDKs.
//
// The first line in this comment block is a short description line and the
// rest is a long description with more detail on the module's purpose or usage,
// if appropriate. All modules should have a short description.

package main

import (
	"context"
	"dagger/cubzh/internal/dagger"
	"fmt"
	"strings"
)

const (
	// Max number of files compiled by Ninja if there are compilation errors
	NB_MAX_BUILD_ERRORS string = "999"
)

type Blip struct{}

// Check code formatting on the entire repository
func (m *Blip) GlobalCodeFormat(
	ctx context.Context,
	// +defaultPath="/"
	// +ignore=["*", "!.clang-format", "!deps/xptools/android"]
	workdir *dagger.Directory,
	// Only check, don't fix
	// +optional
	dryrun bool,
) (*dagger.Directory, error) {

	// ------------------------------------------
	// How to use this function:
	// ------------------------------------------

	// dagger call global-code-format --workdir=. --dryrun=true
	// dagger call global-code-format --workdir=. --dryrun=false

	// ------------------------------------------
	// TODO
	// ------------------------------------------

	// - /core (TODO)
	// - /deps/xptools (TODO)
	//   - /deps/xptools/android (TODO)
	//   - /deps/xptools/common (TODO)
	//   - /deps/xptools/include (TODO)
	//   - /deps/xptools/ios-macos (TODO)
	//   - /deps/xptools/linux (TODO)
	//   - /deps/xptools/web (TODO)
	//   - /deps/xptools/windows (TODO)
	// - /lua/modules (TODO)

	// ------------------------------------------
	// C/C++ source code
	// ------------------------------------------

	// directories containing C/C++ source files
	directories := []string{
		"./deps/xptools/android",
		// ...
	}

	// file selection
	fileSelection := `\( -name "*.h" -o -name "*.hpp" -o -name "*.c" -o -name "*.cpp" \)`

	// clang-format command
	// arguments:
	// -i: apply changes
	// --Werror: consider warnings as errors
	// -style-file: follow the rules from the .clang-format file
	clangFormatCommand := "clang-format"
	if dryrun {
		clangFormatCommand += " --dry-run" // only check formatting
	} else {
		clangFormatCommand += " -i" // apply changes (TODO: gaetan: is this flag really needed?)
	}
	clangFormatCommand += " --Werror"    // consider warnings as errors (TODO: gaetan: maybe this is needed only for dryrun?)
	clangFormatCommand += " -style=file" // follow the rules from the .clang-format file

	// construct script

	var script string
	script += `set -e ; set -o pipefail ; `

	for _, dir := range directories {
		script += `find ` + dir + ` -type f ` + fileSelection + ` -print0 | xargs -0 ` + clangFormatCommand
	}

	// if dryrun {
	// 	script = `
	// 	set -e
	// 	set -o pipefail
	// 	find ./deps/xptools -type f \( -name "*.cpp" -o -name "*.c" \) -print0 | xargs -0 clang-format --dry-run --Werror -style=file
	// 	`
	// } else {
	// 	script = `set -e ; set -o pipefail ; find ./deps/xptools -type f \( -name "*.cpp" -o -name "*.c" \) -print0 | xargs -0 clang-format -i --Werror -style=file`
	// }

	workdir = dag.
		Container().
		From("gaetan/clang-tools").
		WithMountedDirectory("/project", workdir).
		WithWorkdir("/project").
		WithExec([]string{"ash", "-c", script}).
		Directory(".")

	return workdir, nil
}

// Run core unit tests
func (m *Blip) TestCore(
	ctx context.Context,
	// Source code
	// +defaultPath="/"
	// +ignore=["*", "!core", "!deps/libz/linux-x86_64", "!deps/libz/linux-aarch64", "!deps/bgfx/bgfx/3rdparty/cgltf"]
	src *dagger.Directory,
) error {
	// create container with source files
	ctr := dag.Container().From("voxowl/cpp-build-env:18.1.3")

	// retrieve container architecture and provide it as ENVAR inside the container
	{
		platform, err := ctr.Platform(ctx)
		if err != nil {
			return err
		}
		// platform is of the form "linux/arm64"
		// architecture is the second par of the platform string, after the '/'
		architecture := strings.Split(string(platform), "/")[1]
		ctr = ctr.WithEnvVariable("CUBZH_ARCH", architecture)
	}
	_, err := ctr.
		// mount host directory to container and go into it
		WithMountedDirectory("/project", src).
		WithWorkdir("/project/core/tests/cmake").
		// execute build commands
		WithExec([]string{"cmake", "-G", "Ninja", "."}).
		// Flags after `--` are transmitted as-is to the build system (Ninja, here)
		// Ninja will stop if this number of errors is reached : NB_MAX_BUILD_ERRORS
		WithExec([]string{"cmake", "--build", ".", "--clean-first", "--", "-k", NB_MAX_BUILD_ERRORS}).
		// exec compiled unit tests program
		WithExec([]string{"./unit_tests"}).
		Sync(ctx)
	return err
}

// Lint the core source code
func (m *Blip) LintCore(
	ctx context.Context,
	// Core source directory
	// +defaultPath="/"
	// +ignore=["*", "!core", "core/tests/visual_studio", "core/tests/xcode", "core/tests/cmake"]
	src *dagger.Directory,
) error {
	_, err := m.FormatCore(ctx, src, true)
	return err
}

// Format the core source code using clang tools
func (m *Blip) FormatCore(
	ctx context.Context,
	// Source code to format
	// +defaultPath="/"
	// +ignore=["*", "!core", "core/tests/visual_studio", "core/tests/xcode", "core/tests/cmake"]
	src *dagger.Directory,
	// Only check, don't fix
	// +optional
	check bool,
) (*dagger.Directory, error) {
	var script string
	if check {
		// set -e: exit on first error
		// set -o pipefail: keep the last non-0 exit code
		// -regex: all .h / .hpp / .c / .cpp files
		// -maxdepth 2: consider the files in /core and /core/tests
		// // --dry-run: do not apply changes
		script = `set -e ; set -o pipefail ; find ./core -maxdepth 2 -regex '^.*\\.\\(cpp\\|hpp\\|c\\|h\\)$' -print0 | xargs -0 clang-format --dry-run --Werror -style=file`
	} else {
		// -i: apply changes
		// --Werror: consider warnings as errors
		// -style-file: follow the rules from the .clang-format file
		script = `set -e ; set -o pipefail ; find ./core -maxdepth 2 -regex '^.*\\.\\(cpp\\|hpp\\|c\\|h\\)$' -print0 | xargs -0 clang-format -i --Werror -style=file`
	}
	output := dag.
		Container().
		From("gaetan/clang-tools").
		WithMountedDirectory("/project", src).
		WithWorkdir("/project").
		WithExec([]string{"ash", "-c", script}).
		Directory(".")
	if check {
		return output.Sync(ctx)
	}
	return output, nil
}

// // Format the C/C++ source code in /deps/xptools using clang tools
// // Command:
// // dagger call format-xptools --src=. -o .
// func (m *Blip) FormatXPTools(
// 	ctx context.Context,
// 	// Source code to format
// 	// +defaultPath="/"
// 	// +ignore=["*", "!.clang-format", "!deps/xptools/android"]
// 	src *dagger.Directory,
// ) (*dagger.Directory, error) {

// 	// clang-format arguments:
// 	// -i: apply changes
// 	// --Werror: consider warnings as errors
// 	// -style-file: follow the rules from the .clang-format file

// 	// script := `set -e ; set -o pipefail ; find ./deps/xptools -maxdepth 2 -regex '^.*\\.\\(cpp\\|hpp\\|c\\|h\\)$' -print0 | xargs -0 clang-format -i --Werror -style=file`
// 	script := `set -e ; set -o pipefail ; find ./deps/xptools -type f \( -name "*.cpp" -o -name "*.c" \) -print0 | xargs -0 clang-format -i --Werror -style=file`

// 	output := dag.
// 		Container().
// 		From("gaetan/clang-tools").
// 		WithMountedDirectory("/project", src).
// 		WithWorkdir("/project").
// 		WithExec([]string{"ash", "-c", script}).
// 		Directory(".")

// 	// if check {
// 	// 	return output.Sync(ctx)
// 	// }

// 	return output, nil
// }

// Build a Lua dev container with modules source code mounted
func (m *Blip) LuaDev(
	// Lua modules source code
	// +defaultPath="/"
	// +ignore=["*", "!lua/modules"]
	src *dagger.Directory,
) *dagger.Container {
	return dag.
		Container().
		From("voxowl/luadev:1.0").
		WithMountedDirectory("/project", src).
		WithWorkdir("/project")
}

func (m *Blip) LintModules(
	ctx context.Context,
	// Modules source directory
	// +defaultPath="/"
	// +ignore=["*", "!lua/modules"]
	src *dagger.Directory,
) error {
	// _, err := m.
	// 	LuaDev(src).
	// 	WithExec([]string{"luacheck", "."}).
	// 	WithExec([]string{"stylua", "--check", "."}).
	// 	Sync(ctx)
	// return err
	fmt.Println("[🐞] NOT IMPLEMENTED YET")
	return nil
}

// Performs code formatting on Luau modules
// Command:
// dagger call luau-modules-check-format --src=.
func (m *Blip) LuauModulesCheckFormat(
	// +ignore=["*", "!lua/modules"]
	src *dagger.Directory,
) *dagger.Container {

	// Get /cubzh/lua/modules directory
	modules := src.Directory("lua/modules")

	// TODO: gdevillele:
	// - docker image johnnymorganz/stylua:2.0.2 is not available for ARM
	// - make it work for ARM and open a PR on the OSS repo

	return dag.
		Container(dagger.ContainerOpts{Platform: "linux/amd64"}).
		From("johnnymorganz/stylua:2.0.2").
		WithMountedDirectory("/lua/modules", modules).
		WithWorkdir("/lua/modules").
		WithExec([]string{"/stylua", "--check", "."})
}

// TODO: gdevillele:
// I need to find a way to apply the formatting to the source code on the host machine
//
// // Performs code formatting on Luau modules
// func (m *Cubzh) LuauModulesApplyFormat(
// 	// +ignore=["*", "!lua/modules"]
// 	src *dagger.Directory,
// ) *dagger.Container {

// 	// Get /cubzh/lua/modules directory
// 	modules := src.Directory("lua/modules")

// 	// TODO: gdevillele:
// 	// - docker image johnnymorganz/stylua:2.0.2 is not available for ARM
// 	// - make it work for ARM and open a PR on the OSS repo

// 	return dag.
// 		Container(dagger.ContainerOpts{Platform: "linux/amd64"}).
// 		From("johnnymorganz/stylua:2.0.2").
// 		WithMountedDirectory("/lua/modules", modules).
// 		WithWorkdir("/lua/modules").
// 		WithExec([]string{"/stylua", "."})
// }
