module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [2, 'always', [
      'feat', 'fix', 'docs', 'style',
      'refactor', 'perf', 'test', 'build',
      'chore', 'ci', 'sec', 'revert'
    ]],
    'subject-max-length': [2, 'always', 100],
    'subject-case': [2, 'always', 'lower-case'],
    'body-max-line-length': [1, 'always', 200],
  }
};
