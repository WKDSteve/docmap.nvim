import { NextResponse } from "next/server";

/** Says that the service is up. */
export function GET() {
  return NextResponse.json({ ok: true });
}
