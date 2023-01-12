//
//  main.cpp
//  cli
//
//  Created by Gaetan de Villele on 13/10/2022.
//

// C++
#include <iostream>

// cxxopts
#include <cxxopts.hpp>

// cli
#include "combine.hpp"

int main(int argc, const char * argv[]) {

    cxxopts::Options options("Cubzh", "Tools for voxels.");

    options.add_options()
    ("command", "command to use", cxxopts::value<std::string>())
    ("i,input", "input files", cxxopts::value<std::vector<std::string>>())
    // ("n,name", "input file name", cxxopts::value<std::vector<std::string>>())
    ("o,output", "output file", cxxopts::value<std::string>())
    ;

    options.parse_positional({"command"});

    auto result = options.parse(argc, argv);

    // ---------------------------------------------------------------
    const std::string command = result["command"].as<std::string>();
    bool success = false;
    std::string err = "";

    if (command == "combine") {
        success = command_combine(result, err);
    } else {
        err = "command not supported.";
    }

    if (err.empty() == false) {
        std::cout << "ERROR: " << err << std::endl;
    }

    return success ? 0 : 1;
}
