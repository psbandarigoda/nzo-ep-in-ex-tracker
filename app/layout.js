import "./globals.css";
import "./brand.css";

export const metadata = {
  title: "Entertain Passport Balance Sheet",
  description: "nZO x Liyanawicky collaboration ledger"
};

export default function RootLayout({ children }) {
  return <html lang="en"><body suppressHydrationWarning>{children}</body></html>;
}
