module.exports = {
  parser: '@typescript-eslint/parser',
  env: {
    node: true,
  },
  plugins: [
    '@typescript-eslint',
    'import',
  ],
  parserOptions: {
    ecmaVersion: 2018,
    sourceType: 'module',
    ecmaFeatures: {
      jsx: true,
    },
  },
  rules: {
    'comma-dangle': ['error', 'always-multiline'],
    '@typescript-eslint/explicit-function-return-type': 'off',
    'quotes': ['error', 'single'],
    '@typescript-eslint/indent': ['error', 2],
    'import/order': ['error', { 'newlines-between': 'always' }],
    'object-curly-spacing': ['error', 'always'],
    'semi': ['error', 'never'],
  },
  settings: {
    react: {
      version: 'detect',  // Tells eslint-plugin-react to automatically detect the version of React to use
    },
  },
}
