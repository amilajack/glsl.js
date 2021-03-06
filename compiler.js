var glsl = require('./glsl').parser;
var SymbolTable = require('./symbol_table');
var ast = require('./ast');
var escodegen = require('escodegen');

var yy = glsl.yy;
for (var key in ast)
  yy[key] = ast[key];

exports.parse = function(source, options) {
  yy.symbolTable = new SymbolTable();
  yy.loopLevel = 0;
  yy.ignoreMain = options && options.ignoreMain;
  
  return glsl.parse(source);
};

exports.compile = function(source, options) {
  return escodegen.generate(exports.parse(source, options), {
      verbatim: 'verbatim'
  });
};
