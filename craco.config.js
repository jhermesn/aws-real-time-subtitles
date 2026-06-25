const webpack = require('webpack');

module.exports = {
  webpack: {
    configure: (webpackConfig) => {
      // Modern packages (AWS SDK v3) use node: URI scheme; webpack 5 in
      // react-scripts 5.0.1 doesn't handle it. Strip the prefix at resolve time.
      webpackConfig.plugins.push(
        new webpack.NormalModuleReplacementPlugin(/^node:/, (resource) => {
          resource.request = resource.request.replace(/^node:/, '');
        })
      );

      webpackConfig.resolve.fallback = {
        ...webpackConfig.resolve.fallback,
        child_process: false,
      };

      return webpackConfig;
    },
  },
};
