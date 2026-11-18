// Same job as blendRows in repoA, other names, plain JavaScript.
function mixLines(upper, lower, weight) {
  var result = [];
  for (var k = 0; k < upper.length; k++) {
    var left = upper[k] * weight;
    var right = lower[k] * (1 - weight);
    result.push(Math.round(left + right));
  }
  if (result.length === 0) {
    return [];
  }
  return result;
}

module.exports = { mixLines };
