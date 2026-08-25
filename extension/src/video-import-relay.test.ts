// SPDX-License-Identifier: MIT

import { describe, expect, it, vi } from "vitest";

import { PROTOCOL_VERSION, type VideoImportRequest, type VideoImportResponse } from "./protocol.js";
import { relayVideoImportPort, type RelayPort } from "./video-import-relay.js";

class ListenerEvent<T extends (...args: never[]) => void> {
  private readonly listeners = new Set<T>();

  addListener(listener: T): void {
    this.listeners.add(listener);
  }

  removeListener(listener: T): void {
    this.listeners.delete(listener);
  }

  emit(...args: Parameters<T>): void {
    for (const listener of this.listeners) listener(...args);
  }
}

class FakeRelayPort implements RelayPort {
  readonly onMessage = new ListenerEvent<(message: unknown) => void>();
  readonly onDisconnect = new ListenerEvent<() => void>();
  readonly sent: unknown[] = [];
  disconnected = false;

  postMessage(message: unknown): void {
    this.sent.push(message);
  }

  disconnect(): void {
    this.disconnected = true;
  }

  receive(message: unknown): void {
    this.onMessage.emit(message);
  }

  drop(): void {
    this.onDisconnect.emit();
  }
}

const ack: VideoImportResponse = { protocol_version: PROTOCOL_VERSION, ok: true };

function begin(): VideoImportRequest {
  return {
    protocol_version: PROTOCOL_VERSION,
    action: "video_import_begin",
    upload_id: "one-upload",
    metadata: {
      kind: "video",
      url: "https://www.cosmos.so/e/2035271300",
      canonical_url: "https://www.cosmos.so/e/2035271300",
      title: "Cosmos",
      saved_at: "2026-08-25T15:00:00.000Z",
    },
    content_type: "video/mp4",
  };
}

function chunk(sequence: number): VideoImportRequest {
  return {
    protocol_version: PROTOCOL_VERSION,
    action: "video_import_chunk",
    upload_id: "one-upload",
    sequence,
    data_base64: "AA==",
  };
}

describe("video import worker relay", () => {
  it("opens one native port and does not forward another chunk before its acknowledgement", () => {
    const tab = new FakeRelayPort();
    const native = new FakeRelayPort();
    const connectNative = vi.fn(() => native);
    relayVideoImportPort(tab, connectNative);

    tab.receive(begin());
    tab.receive(chunk(0));
    tab.receive(chunk(1));
    expect(connectNative).toHaveBeenCalledTimes(1);
    expect(native.sent).toEqual([begin()]);

    native.receive(ack);
    expect(tab.sent).toEqual([ack]);
    expect(native.sent).toEqual([begin(), chunk(0)]);

    native.receive(ack);
    expect(tab.sent).toEqual([ack, ack]);
    expect(native.sent).toEqual([begin(), chunk(0), chunk(1)]);
  });

  it("waits for an in-flight acknowledgement, then aborts the same upload when the tab port dies", () => {
    const tab = new FakeRelayPort();
    const native = new FakeRelayPort();
    relayVideoImportPort(tab, () => native);

    tab.receive(begin());
    tab.drop();
    expect(native.sent).toEqual([begin()]);

    native.receive(ack);
    expect(native.sent).toEqual([
      begin(),
      {
        protocol_version: PROTOCOL_VERSION,
        action: "video_import_abort",
        upload_id: "one-upload",
      },
    ]);

    native.receive(ack);
    expect(native.disconnected).toBe(true);
  });

  it("forwards the browser's native disconnect reason to the tab", () => {
    const tab = new FakeRelayPort();
    const native = new FakeRelayPort();
    relayVideoImportPort(
      tab,
      () => native,
      () => "Specified native messaging host not found.",
    );

    native.drop();

    expect(tab.sent).toEqual([
      {
        protocol_version: PROTOCOL_VERSION,
        ok: false,
        error: "native_connection",
        message: "Specified native messaging host not found.",
      },
    ]);
    expect(tab.disconnected).toBe(true);
  });
});
