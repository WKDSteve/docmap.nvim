import type { AppProps } from "next/app";

/** The frame of every legacy page. */
export default function App({ Component, pageProps }: AppProps) {
  return <Component {...pageProps} />;
}
