import React from 'react';
import ReactDOM from 'react-dom/client';
import { Buffer } from 'buffer'; // NOSONAR - browser polyfill pkg, not node:buffer
import process from 'process'; // NOSONAR - browser polyfill pkg, not node:process
import '@cloudscape-design/global-styles/index.css';
import './index.css';
import App from './App';

// webpack 5 removed Node polyfills; restore globals required by AWS SDK streaming
// @ts-ignore
globalThis.Buffer = Buffer;
if (!('process' in globalThis)) {
  // @ts-ignore
  globalThis.process = process;
}

const root = ReactDOM.createRoot(document.getElementById('root') as HTMLElement);
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
