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
import { hasLibraryData, readAccounts } from "./archive";
import {
  exportAccounts,
  refreshAccounts,
  restoreAccounts,
  useAccounts,
  validateAccounts,
} from "../../stores/accountsStorage";
import { accountSites, type AccountCredentials } from "../../types/accounts";
import type { Archive } from "../../types/library";
import { platforms } from "../../app/platforms";
import { updatePreferences, usePreferences } from "../../stores/preferencesStorage";

interface Props {
  active: boolean;
  data: Library;
  commit: (data: Library, expected: Library) => Promise<void>;
  notify: (message: string) => void;
}
interface Remote {
  missing?: boolean;
  data?: string;
  etag?: string;
}
export function Sync({ active, data, commit, notify }: Props) {
  const { modal } = AntApp.useApp();
  const accounts = useAccounts(active);
  const { data: preferences, error: preferencesError } = usePreferences();
  const { url, username, password } = preferences.webdav;
  const [tab, setTab] = useState("webdav");
  const [selection, setSelection] = useState<Selection>({
    follows: true,
    histories: true,
    blocked: true,
    bilibili: false,
    douyu: false,
    douyin: false,
  });
  const [replace, setReplace] = useState(false);
  const [address, setAddress] = useState("");
  const [busy, setBusy] = useState("");
  const [status, setStatus] = useState("");
  const [failed, setFailed] = useState(false);
  const [lastSync, setLastSync] = useState("");
  const file = useRef<HTMLInputElement>(null);
  const locked = useRef(false);
  const chosen = Object.values(selection).some(Boolean);
  const selectedAccounts = accountSites.filter((site) => selection[site]);

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
  async function confirmAccounts(outbound: boolean) {
    return modal.confirm({
      title: outbound ? "同步账号凭据？" : "恢复账号凭据？",
      content: outbound
        ? "账号凭据包含登录授权，将以明文写入备份或传输至设备。请仅使用可信的存储和设备，勿分享备份文件。"
        : "非空凭据会替换所选平台当前的登录授权；覆盖模式下空凭据也会清除账号。",
      okButtonProps: { danger: true },
    });
  }
  async function archiveCredentials(): Promise<AccountCredentials> {
    if (!selectedAccounts.length) return {};
    const snapshot = await refreshAccounts();
    return exportAccounts(selectedAccounts, snapshot.revision);
  }
  async function applyArchive(files: Archive) {
    const hasLibrary = hasLibraryData(files, selection);
    const incoming = readAccounts(files, selection);
    const hasAccounts = Object.keys(incoming).length > 0;
    if (!hasLibrary && !hasAccounts) throw new Error("备份中没有所选类型的数据，未修改本地数据");
    const next = hasLibrary ? restore(data, files, selection, replace) : data;
    // Validate both files before either independent local store is changed.
    if (hasAccounts) await validateAccounts(incoming);
    if (!(await confirmRestore())) return false;
    if (hasAccounts && !(await confirmAccounts(false))) return false;
    const patch: AccountCredentials = {};
    for (const site of accountSites) {
      if (incoming[site] !== undefined && (replace || incoming[site]?.trim()))
        patch[site] = incoming[site];
    }
    const snapshot = Object.keys(patch).length ? await refreshAccounts() : null;
    if (hasLibrary) await commit(next, data);
    if (snapshot) {
      try { await restoreAccounts(patch, snapshot.revision); }
      catch {
        throw new Error(hasLibrary
          ? "列表数据已恢复，但账号恢复失败，无法自动回滚，请只选择账号重试"
          : "账号恢复失败，请刷新账号状态后重试");
      }
    }
    return true;
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
    if (
      action === "upload" &&
      !(await modal.confirm({
        title: "更新云端备份？",
        content: "将更新所选数据，其他文件保持不变。",
      }))
    )
      return;
    if (action === "upload" && selectedAccounts.length && !(await confirmAccounts(true))) return;
    const remote = await api<Remote>("webdav", {
      ...credentials,
      action: "download",
    });
    if (action === "download") {
      if (remote.missing || !remote.data)
        throw new Error("云端还没有 backup.zip 备份");
      if (await applyArchive(readArchive(fromBase64(remote.data))))
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
      const credentialsData = await archiveCredentials();
      await api("webdav", {
        ...credentials,
        action: "upload",
        data: toBase64(makeArchive(data, selection, base, credentialsData)),
        etag: remote.etag,
        missing: remote.missing,
      });
      complete("数据已上传至云端");
    }
  }
  async function push() {
    if (!address.trim()) throw new Error("请填写设备 IP 地址");
    if (!chosen) throw new Error("请选择至少一项同步数据");
    if (selection.douyin) throw new Error("设备协议不支持抖音账号，请使用 ZIP 或 WebDAV");
    if (
      !(await modal.confirm({
        title: `${replace ? "覆盖" : "合并"}设备 ${address} 上的所选数据？`,
        okButtonProps: { danger: replace },
      }))
    )
      return;
    if (selectedAccounts.length && !(await confirmAccounts(true))) return;
    await api("device", { address: address.trim(), kind: "info" });
    const accountSnapshot = selectedAccounts.length ? await refreshAccounts() : null;
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
      ...selectedAccounts.map((site): [string, unknown, string] => [
        `account/${site}`, undefined, `${platforms.find((item) => item.id === site)?.name}账号`,
      ]),
    ];
    const completed: string[] = [];
    for (const [kind, payload, label] of entries) {
      try {
        await api("device", {
          address: address.trim(),
          kind,
          data: payload,
          overlay: replace,
          revision: accountSnapshot?.revision,
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
        onChange={(value) => {
          setTab(value);
          if (value === "device") setSelection((current) => ({ ...current, douyin: false }));
        }}
        items={[
          { key: "webdav", label: "WebDAV", icon: <Cloud size={18} />, disabled: !!busy },
          { key: "device", label: "局域网", icon: <Monitor size={18} />, disabled: !!busy },
          { key: "file", label: "本地备份", icon: <FolderArchive size={18} />, disabled: !!busy },
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
            {accountSites.map((site) => {
              const account = accounts.data?.items.find((item) => item.site === site);
              const label = `${platforms.find((item) => item.id === site)?.name}${site === "douyin" ? " ttwid" : "账号"}`;
              return (
                <label className="setting-row" key={site}>
                  <span>{label}<small>{accounts.error ? "读取失败" : !accounts.data ? "未读取" : account?.configured ? "已保存" : "未配置"}</small></span>
                  <Switch aria-label={label} checked={selection[site]}
                    disabled={tab === "device" && site === "douyin"}
                    onChange={(checked) => setSelection({ ...selection, [site]: checked })} />
                </label>
              );
            })}
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
                  disabled={!!preferencesError}
                  maxLength={4096}
                  value={url}
                  onChange={(event) => updatePreferences({ webdav: { url: event.target.value } })}
                />
              </label>
              <div className="form-grid">
                <label className="field">
                  用户名
                  <Input
                    autoComplete="username"
                    disabled={!!preferencesError}
                    maxLength={2048}
                    value={username}
                    onChange={(event) => updatePreferences({ webdav: { username: event.target.value } })}
                  />
                </label>
                <label className="field">
                  密码
                  <Input.Password
                    autoComplete="off"
                    disabled={!!preferencesError}
                    maxLength={8192}
                    value={password}
                    onChange={(event) => updatePreferences({ webdav: { password: event.target.value } })}
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
                      if (selectedAccounts.length && !(await confirmAccounts(true))) return;
                      const credentialsData = await archiveCredentials();
                      download(
                        makeArchive(data, selection, {}, credentialsData),
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
                    if (await applyArchive(readArchive(
                      new Uint8Array(await selected.arrayBuffer()),
                    ))) complete("备份已导入");
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
