import { useRef, useState } from "react";
import {
  App as AntApp,
  Button,
  ConfigProvider,
  Input,
  Segmented,
  Switch,
  Tabs,
} from "antd";
import {
  Cloud,
  Download,
  Upload,
  FolderArchive,
  Monitor,
  Link,
  Check,
  LoaderCircle,
} from "lucide-react";
import {
  api,
  download,
  fromBase64,
  makeArchive,
  readArchive,
  restore,
  toBase64,
  type Library,
  type Selection,
} from "../../services/libraryData";

interface Props {
  data: Library;
  commit: (data: Library, expected: Library) => Promise<void>;
  notify: (message: string) => void;
}
interface Remote {
  missing?: boolean;
  data?: string;
  etag?: string;
}
export function Sync({ data, commit, notify }: Props) {
  const { modal } = AntApp.useApp();
  const [tab, setTab] = useState("webdav");
  const [selection, setSelection] = useState<Selection>({
    follows: true,
    histories: true,
    blocked: true,
  });
  const [replace, setReplace] = useState(false);
  const [url, setUrl] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [address, setAddress] = useState("");
  const [busy, setBusy] = useState("");
  const [status, setStatus] = useState("");
  const [failed, setFailed] = useState(false);
  const [lastSync, setLastSync] = useState("");
  const file = useRef<HTMLInputElement>(null);
  const locked = useRef(false);
  const chosen = Object.values(selection).some(Boolean);

  async function run(label: string, action: () => Promise<void>) {
    if (locked.current) return;
    locked.current = true;
    setBusy(label);
    setStatus("");
    setFailed(false);
    try {
      await action();
    } catch (error) {
      setFailed(true);
      setStatus(error instanceof Error ? error.message : "同步失败");
    } finally {
      locked.current = false;
      setBusy("");
    }
  }
  function complete(message: string) {
    setStatus(message);
    setLastSync(new Date().toLocaleString("zh-CN"));
    notify(message);
  }
  async function confirmRestore() {
    return (
      !replace ||
      (await modal.confirm({
        title: "覆盖本地所选数据？",
        content: "空列表也会覆盖原有数据，此操作不可撤销。",
        okButtonProps: { danger: true },
      }))
    );
  }
  async function cloud(action: "check" | "download" | "upload") {
    const credentials = { url: url.trim(), username, password };
    if (!url.trim()) throw new Error("请填写 WebDAV 地址");
    if (
      url.trim().startsWith("http:") &&
      !(await modal.confirm({
        title: "继续使用 HTTP 连接？",
        content: "此 WebDAV 地址未启用 HTTPS，账号密码将以明文传输。",
      }))
    )
      return;
    if (action === "check") {
      await api("webdav", { ...credentials, action });
      setStatus("连接成功");
      return;
    }
    if (!chosen) throw new Error("请选择至少一项同步数据");
    if (action === "download" && !(await confirmRestore())) return;
    if (
      action === "upload" &&
      !(await modal.confirm({
        title: "更新云端备份？",
        content: "将更新所选数据，其他文件保持不变。",
      }))
    )
      return;
    const remote = await api<Remote>("webdav", {
      ...credentials,
      action: "download",
    });
    if (action === "download") {
      if (remote.missing || !remote.data)
        throw new Error("云端还没有 backup.zip 备份");
      await commit(
        restore(data, readArchive(fromBase64(remote.data)), selection, replace),
        data,
      );
      complete("云端数据已恢复");
    } else {
      const base = remote.missing ? {} : readArchive(fromBase64(remote.data!));
      if (
        !remote.missing &&
        (!remote.etag || remote.etag.startsWith("W/")) &&
        !(await modal.confirm({
          title: "继续覆盖云端所选数据？",
          content:
            "服务器没有提供有效的版本标识，无法检测其他设备的并发修改。请确认其他设备没有正在同步。",
          okButtonProps: { danger: true },
        }))
      )
        return;
      await api("webdav", {
        ...credentials,
        action: "upload",
        data: toBase64(makeArchive(data, selection, base)),
        etag: remote.etag,
        missing: remote.missing,
      });
      complete("数据已上传至云端");
    }
  }
  async function push() {
    if (!address.trim()) throw new Error("请填写设备 IP 地址");
    if (!chosen) throw new Error("请选择至少一项同步数据");
    if (
      !(await modal.confirm({
        title: `${replace ? "覆盖" : "合并"}设备 ${address} 上的所选数据？`,
        okButtonProps: { danger: replace },
      }))
    )
      return;
    await api("device", { address: address.trim(), kind: "info" });
    const entries: [string, unknown, string][] = [
      ...(selection.follows
        ? ([
            ["follow", data.follows, "关注"],
            ["tag", data.tags, "标签"],
          ] as [string, unknown, string][])
        : []),
      ...(selection.histories
        ? ([["history", data.histories, "历史记录"]] as [
            string,
            unknown,
            string,
          ][])
        : []),
      ...(selection.blocked
        ? ([["blocked_word", data.blocked, "屏蔽词"]] as [
            string,
            unknown,
            string,
          ][])
        : []),
    ];
    const completed: string[] = [];
    for (const [kind, payload, label] of entries) {
      try {
        await api("device", {
          address: address.trim(),
          kind,
          data: payload,
          overlay: replace,
        });
        completed.push(label);
      } catch {
        throw new Error(
          `${label}传输失败。${completed.length ? `已传输：${completed.join("、")}；设备端无法回滚，请重新推送。` : "请检查设备地址和同步服务。"}`,
        );
      }
    }
    complete("已推送至局域网设备");
  }

  return (
    <div className="settings-content">
      <div className="section-heading">
        <div>
          <h2>数据同步</h2>
          <span className="muted">
            {lastSync ? `最近同步：${lastSync}` : "尚未同步"}
          </span>
        </div>
        <Cloud size={28} className="accent" />
      </div>
      <Tabs
        aria-label="同步方式"
        activeKey={tab}
        onChange={setTab}
        items={[
          { key: "webdav", label: "WebDAV", icon: <Cloud size={18} /> },
          { key: "device", label: "局域网", icon: <Monitor size={18} /> },
          { key: "file", label: "本地备份", icon: <FolderArchive size={18} /> },
        ]}
      />
      <ConfigProvider componentDisabled={!!busy}>
        <fieldset disabled={!!busy} className="sync-fields">
          <section className="setting-section">
            <h3>同步内容</h3>
            {(
              [
                [
                  "follows",
                  "关注与标签",
                  `${data.follows.length} 位主播 · ${data.tags.length} 个标签`,
                ],
                ["histories", "历史记录", `${data.histories.length} 条记录`],
                ["blocked", "弹幕屏蔽词", `${data.blocked.length} 个屏蔽词`],
              ] as const
            ).map(([key, label, count]) => (
              <label className="setting-row" key={key}>
                <span>
                  {label}
                  <small>{count}</small>
                </span>
                <Switch
                  aria-label={label}
                  checked={selection[key]}
                  onChange={(checked) =>
                    setSelection({ ...selection, [key]: checked })
                  }
                />
              </label>
            ))}
            <div className="setting-row">
              <span>恢复与推送方式</span>
              <Segmented
                value={replace ? "replace" : "merge"}
                onChange={(value) => setReplace(value === "replace")}
                options={[
                  { value: "merge", label: "合并" },
                  { value: "replace", label: "覆盖" },
                ]}
              />
            </div>
          </section>
          {tab === "webdav" && (
            <section className="setting-section">
              <h3>WebDAV 连接</h3>
              <label className="field">
                服务器地址
                <Input
                  type="url"
                  placeholder="https://dav.example.com/dav/"
                  autoComplete="url"
                  value={url}
                  onChange={(event) => setUrl(event.target.value)}
                />
              </label>
              <div className="form-grid">
                <label className="field">
                  用户名
                  <Input
                    autoComplete="username"
                    value={username}
                    onChange={(event) => setUsername(event.target.value)}
                  />
                </label>
                <label className="field">
                  密码
                  <Input.Password
                    autoComplete="off"
                    value={password}
                    onChange={(event) => setPassword(event.target.value)}
                  />
                </label>
              </div>
              <div className="actions">
                <Button
                  icon={<Link size={16} />}
                  onClick={() => run("连接中", () => cloud("check"))}
                >
                  检查连接
                </Button>
                <Button
                  icon={<Download size={16} />}
                  disabled={!!busy || !chosen}
                  onClick={() => run("恢复中", () => cloud("download"))}
                >
                  恢复到本地
                </Button>
                <Button
                  type="primary"
                  icon={<Upload size={16} />}
                  disabled={!!busy || !chosen}
                  onClick={() => run("上传中", () => cloud("upload"))}
                >
                  上传到云端
                </Button>
              </div>
            </section>
          )}
          {tab === "device" && (
            <section className="setting-section">
              <h3>局域网设备</h3>
              <label className="field">
                设备 IP 地址
                <Input
                  placeholder="192.168.1.100"
                  value={address}
                  onChange={(event) => setAddress(event.target.value)}
                />
              </label>
              <div className="actions">
                <Button
                  icon={<Link size={16} />}
                  onClick={() =>
                    run("连接中", async () => {
                      const info = await api<{
                        name: string;
                        type: string;
                        version: string;
                      }>("device", { address: address.trim(), kind: "info" });
                      setStatus(
                        `已连接 ${info.name} · ${info.type} · ${info.version}`,
                      );
                    })
                  }
                >
                  检查连接
                </Button>
                <Button
                  type="primary"
                  icon={<Upload size={16} />}
                  disabled={!!busy || !chosen}
                  onClick={() => run("推送中", push)}
                >
                  推送到设备
                </Button>
              </div>
            </section>
          )}
          {tab === "file" && (
            <section className="setting-section">
              <h3>本地备份</h3>
              <div className="actions">
                <Button
                  disabled={!!busy || !chosen}
                  icon={<Download size={16} />}
                  onClick={() => file.current?.click()}
                >
                  导入 ZIP
                </Button>
                <Button
                  type="primary"
                  icon={<Upload size={16} />}
                  disabled={!!busy || !chosen}
                  onClick={() =>
                    run("导出中", async () => {
                      download(
                        makeArchive(data, selection),
                        `SimpleLive_${new Date().toISOString().slice(0, 10)}.zip`,
                      );
                      setStatus("备份已导出");
                    })
                  }
                >
                  导出 ZIP
                </Button>
              </div>
              <input
                ref={file}
                hidden
                type="file"
                accept=".zip,application/zip"
                onChange={(event) => {
                  const selected = event.target.files?.[0];
                  event.target.value = "";
                  if (!selected) return;
                  void run("导入中", async () => {
                    if (selected.size > 20 * 1024 * 1024)
                      throw new Error("备份不能超过 20 MB");
                    if (!(await confirmRestore())) return;
                    await commit(
                      restore(
                        data,
                        readArchive(
                          new Uint8Array(await selected.arrayBuffer()),
                        ),
                        selection,
                        replace,
                      ),
                      data,
                    );
                    complete("备份已导入");
                  });
                }}
              />
            </section>
          )}
        </fieldset>
      </ConfigProvider>
      {(busy || status) && (
        <div role="status" className={`sync-status ${failed ? "error" : ""}`}>
          {busy ? (
            <LoaderCircle className="spin" size={18} />
          ) : (
            !failed && <Check size={18} />
          )}
          {busy || status}
        </div>
      )}
    </div>
  );
}
