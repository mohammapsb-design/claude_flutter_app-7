/// A tiny, self-contained recursive-descent evaluator for arithmetic
/// expressions like "2 + 2 * (3 - 1)". No external package needed, and no
/// eval() — it only ever does arithmetic, so it's safe to run on whatever
/// text the model sends.
class ExpressionEvaluator {
  final String _input;
  int _pos = 0;

  ExpressionEvaluator(String input) : _input = input.replaceAll(' ', '');

  static double evaluate(String expression) {
    final evaluator = ExpressionEvaluator(expression);
    final result = evaluator._parseExpression();
    if (evaluator._pos != evaluator._input.length) {
      throw FormatException('Unexpected character at position ${evaluator._pos}');
    }
    return result;
  }

  String get _current => _pos < _input.length ? _input[_pos] : '';

  double _parseExpression() {
    var value = _parseTerm();
    while (_current == '+' || _current == '-') {
      final op = _current;
      _pos++;
      final rhs = _parseTerm();
      value = op == '+' ? value + rhs : value - rhs;
    }
    return value;
  }

  double _parseTerm() {
    var value = _parseFactor();
    while (_current == '*' || _current == '/' || _current == '%') {
      final op = _current;
      _pos++;
      final rhs = _parseFactor();
      if (op == '*') {
        value = value * rhs;
      } else if (op == '/') {
        value = value / rhs;
      } else {
        value = value % rhs;
      }
    }
    return value;
  }

  double _parseFactor() {
    if (_current == '+') {
      _pos++;
      return _parseFactor();
    }
    if (_current == '-') {
      _pos++;
      return -_parseFactor();
    }
    if (_current == '(') {
      _pos++;
      final value = _parseExpression();
      if (_current != ')') throw const FormatException('Missing closing parenthesis');
      _pos++;
      return _parsePower(value);
    }
    return _parsePower(_parseNumber());
  }

  double _parsePower(double base) {
    if (_current == '^') {
      _pos++;
      final exponent = _parseFactor();
      return _pow(base, exponent);
    }
    return base;
  }

  double _pow(double base, double exponent) {
    var result = 1.0;
    final isNegative = exponent < 0;
    final count = exponent.abs().round();
    for (var i = 0; i < count; i++) {
      result *= base;
    }
    return isNegative ? 1 / result : result;
  }

  double _parseNumber() {
    final start = _pos;
    while (_pos < _input.length &&
        (RegExp(r'[0-9.]').hasMatch(_input[_pos]))) {
      _pos++;
    }
    if (start == _pos) {
      throw FormatException('Expected a number at position $_pos');
    }
    return double.parse(_input.substring(start, _pos));
  }
}
