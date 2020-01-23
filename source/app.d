import std.stdio, std.file, std.array, std.string, std.getopt, std.path, std.regex, std.random, std.process;
import core.stdc.stdlib;
import language.grammar;
import program;
import std.conv;
import globals;
import optimizer;
import dini;

int line_count = 0;

/**
 * Application entry point
 */

bool noopt = false;
string output_type = "prg";
string compiler_version = "v2.2.02";


void main(string[] args)
{
    Ini conf = get_conf();

    if(args.length < 2) {
        stderr.writeln("Error: input file not specified");
        exit(1);
    }

    auto helpInformation = getopt(args,
        "noopt|n", &noopt,
        "output|o", &output_type
    );

    if(helpInformation.helpWanted) {
        display_help();
    }

    if(output_type != "prg" && output_type != "asm") {
        stderr.writeln("Invalid value for option -o");
        exit(1);
    }

    string filename = args[1];
    string outname = args[2];

    string source = build_source(filename);
    auto ast = XCBASIC(source);

    if(!ast.successful) {
        auto lines = splitLines(to!string(ast));
        string line = lines[$-1];
        stderr.writeln("Parser error: " ~ strip(line, " +-"));
        //stderr.writeln(ast);
        exit(1);
    }

    //stderr.writeln(ast); exit(1);

    auto program = new Program();
    program.source_path = absolutePath(dirName(filename));
    program.processAst(ast);
    string code = program.getAsmCode();
    if(!noopt) {
        auto optimizer = new Optimizer(code);
        optimizer.run();
        code = optimizer.outcode;
    }

    if(output_type == "prg") {

        // Write assembly program to temp location
        string tmpDir = tempDir();
        auto rnd = Random(42);
        auto u = uniform!uint(rnd);
        string asm_filename = tempDir() ~ "/xcbtmp_" ~ to!string(u, 16) ~ ".asm";
        File outfile = File(asm_filename, "w");
        outfile.write(code);
        outfile.close();

        // Get DASM executable path
        string path = dirName(thisExePath());
        string dasm_bin = path ~ dirSeparator ~ conf["assembler"].getKey("dasm_bin");

        // Assemble!
        auto dasm = executeShell(dasm_bin ~ " " ~ asm_filename ~ " -o" ~ outname);
        if(dasm.status != 0) {
            stderr.writeln("There has been an error while trying to execute DASM, please see the bellow message.");
            stderr.writeln(dasm.output);

            // Remove temp file and exit
            remove(asm_filename);
            exit(1);
        }
        else {

            // Remove temp file and exit
            remove(asm_filename);
            stdout.write(dasm.output);
            exit(0);
        }


    }
    else {
        File outfile = File(outname, "w");
        outfile.write(code);
        outfile.close();
        stdout.writeln("Complete.");
        exit(0);
    }
}

/**
 * Recursively builds a source string from file
 * along with its includes
 */

string build_source(string filename)
{
    File infile;

    try {
        infile = File(filename, "r");
    }
    catch(Exception e) {
        stderr.writeln("Failed to open source file (" ~ filename ~ ")");
        exit(1);
    }

    string source = "";

    int local_line_count = 0;
    while(!infile.eof){

        line_count++;
        local_line_count++;

        globals.source_file_map~=baseName(filename);
        globals.source_line_map~=local_line_count;

        string line = strip(infile.readln(), "\n");
        source = source ~ line ~ "\n";

        auto ast = XCBASIC(line);
        auto bline = ast.children[0].children[0];
        foreach(ref node; bline.children) {
            if(node.name == "XCBASIC.Statements") {
                foreach(ref statement; node.children) {
                    if(statement.children[0].name == "XCBASIC.Include_stmt") {
                        string fname = join(statement.children[0].children[0].matches[1..$-1]);
                        string path = absolutePath(dirName(filename)) ~ "/" ~ fname;
                        source ~= build_source(path);
                    }
                }
            }
        }
    }

    return source;
}

/**
 * Display help message and exit
 */

void display_help()
{
    stdout.writeln(
`
XC=BASIC compiler version ` ~ compiler_version ~ `
Copyright (c) 2019-2020 by Csaba Fekete
Usage: xcbasic64 [options] <inputfile> <outputfile> [options]
Options:
  --output=<x> or -o<x>  Output type: "prg" (default) or "asm"
  --noopt or -n          Do not run the optimizer (defaults to false)
  --help or -h           Show this help
`
    );
    exit(0);
}

/**
 * Fetch configuration file
 */

Ini get_conf()
{
    string path = dirName(thisExePath());
    string filename = path ~ dirSeparator ~ "xcbasic.conf";
    try {
        return Ini.Parse(filename);
    }
    catch(Exception e) {
        stderr.writeln("Could not find configuration file in " ~ filename);
        exit(1);
    }

    assert(0);
}
