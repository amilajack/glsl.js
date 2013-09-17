var glsl = require('../compiler');
var assert = require('assert');
var fs = require('fs');

var BOILERPLATE = fs.readFileSync(__dirname + '/data/boilerplate.js', 'utf8');

function compare(a, b) {
    assert.equal(a.replace(/[\s\n\r]*/g, ''), b.replace(/[\s\n\r]*/g, ''));
}

function checkMain(a, b) {
    compare(a.split('\n').slice(5, -6).join('\n'), b);
}

describe('main function', function() {
    
    it('should throw an error without a main function', function() {
        assert.throws(function() {
            glsl.compile('');
        }, /Parse error/);
    });
    
    it('should throw an error if main function returns incorrect type', function() {
        assert.throws(function() {
            glsl.compile('int main() {}');
        }, /main function must return void/);
    });
    
    it('should throw an error if main function accepts arguments', function() {
        assert.throws(function() {
            glsl.compile('void main(int a) {}')
        }, /No main function found/);
    });
    
    it('should throw an error if main function doesn\'t have a body', function() {
        assert.throws(function() {
            glsl.compile('void main();');
        }, /No main function found/);
    });
    
    it('should generate asm.js boilerplate', function() {
        compare(glsl.compile('void main() {}'), BOILERPLATE);
    });
    
});

describe('primative variable declarations', function() {
    
    it('should default ints to 0', function() {
        checkMain(glsl.compile('void main() { int test; }'), 'function main() { var test = 0; }');
    });
    
    it('should default floats to 0.0', function() {
        checkMain(glsl.compile('void main() { float test; }'), 'function main() { var test = (0.0); }');
    });
    
    it('should default bools to 0 (false)', function() {
        checkMain(glsl.compile('void main() { bool test; }'), 'function main() { var test = 0; }');
    });
        
});

describe('primative variable initializers', function() {
    it('should allow valid int initializations', function() {
        checkMain(glsl.compile('void main() { int test = 1; }'),    'function main() { var test = 1; }');
        checkMain(glsl.compile('void main() { int test = 55; }'),   'function main() { var test = 55; }');
        checkMain(glsl.compile('void main() { int test = 0x23; }'), 'function main() { var test = 35; }');
        checkMain(glsl.compile('void main() { int test = 023; }'),  'function main() { var test = 19; }');
    });
        
    it('should allow valid float initializations', function() {
        checkMain(glsl.compile('void main() { float test = 1.0; }'),    'function main() { var test = (1.0); }');
        checkMain(glsl.compile('void main() { float test = .04; }'),    'function main() { var test = 0.04; }');
        checkMain(glsl.compile('void main() { float test = 0.50; }'),   'function main() { var test = 0.5; }');
        checkMain(glsl.compile('void main() { float test = 55.23; }'),  'function main() { var test = 55.23; }');
        checkMain(glsl.compile('void main() { float test = 5e3; }'),    'function main() { var test = (5000.0); }');
        checkMain(glsl.compile('void main() { float test = 5.5e3; }'),  'function main() { var test = (5500.0); }');
        checkMain(glsl.compile('void main() { float test = 5.5e-3; }'), 'function main() { var test = 0.0055; }');
        checkMain(glsl.compile('void main() { float test = .5e3; }'),   'function main() { var test = (500.0); }');
    });
    
    it('should allow valid bool initializations', function() {
        checkMain(glsl.compile('void main() { bool test = true; }'),  'function main() { var test = 1; }');
        checkMain(glsl.compile('void main() { bool test = false; }'), 'function main() { var test = 0; }');
    });
    
    it('should throw on invalid int initializations', function() {
        assert.throws(function() {
            glsl.compile('void main() { int test = 1.0; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { int test = .04; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { int test = 0.50; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { int test = 55.23; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { int test = 5e3; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { int test = 5.5e3; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { int test = 5.5e-3; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { int test = .5e3; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { int test = true; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { int test = false; }');
        }, /Left and right arguments are of differing types/);
    });
    
    
    it('should throw on invalid float initializations', function() {
        assert.throws(function() {
            glsl.compile('void main() { float test = 1; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { float test = 55; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { float test = 0x23; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { float test = 023; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { float test = true; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { float test = false; }');
        }, /Left and right arguments are of differing types/);
    });
    
    it('should throw on invalid bool initializations', function() {
        assert.throws(function() {
            glsl.compile('void main() { bool test = 1; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { bool test = 55; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { bool test = 0x23; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { bool test = 023; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { bool test = 1.0; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { bool test = .04; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { bool test = 0.50; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { bool test = 55.23; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { bool test = 5e3; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { bool test = 5.5e3; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { bool test = 5.5e-3; }');
        }, /Left and right arguments are of differing types/);
        
        assert.throws(function() {
            glsl.compile('void main() { bool test = .5e3; }');
        }, /Left and right arguments are of differing types/);
    });
    
})