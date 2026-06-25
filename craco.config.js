const webpack = require('webpack');

module.exports = {
  webpack: {
    configure: (webpackConfig) => {
      // AWS SDK v3 uses node: URI scheme; webpack 5 in react-scripts 5.0.1 doesn't handle it
      webpackConfig.plugins.push(
        new webpack.NormalModuleReplacementPlugin(/^node:/, (resource) => {
          resource.request = resource.request.replace(/^node:/, '');
        })
      );

      // AWS SDK v3 references Node core modules that don't exist in browsers
      webpackConfig.resolve.fallback = {
        ...webpackConfig.resolve.fallback,
        crypto: require.resolve('crypto-browserify'),
        stream: require.resolve('stream-browserify'),
        os: require.resolve('os-browserify/browser'),
        path: require.resolve('path-browserify'),
        https: require.resolve('https-browserify'),
        http: require.resolve('stream-http'),
        assert: require.resolve('assert/'),
        util: require.resolve('util/'),
        buffer: require.resolve('buffer/'),
        process: require.resolve('process/browser'),
        child_process: false,
        fs: false,
        net: false,
        tls: false,
        dns: false,
      };

      // Make Buffer and process available globally (some AWS SDK modules expect them)
      webpackConfig.plugins.push(
        new webpack.ProvidePlugin({
          Buffer: ['buffer', 'Buffer'],
          process: 'process/browser',
        })
      );

      return webpackConfig;
    },
  },
};
