import { useEffect, useRef, useState } from "react";
import { App as AntApp, Alert, Button, Input, Modal, QRCode, Tabs, Tag, Tooltip } from "antd";
import { LogIn, LogOut, RefreshCw, UsersRound } from "lucide-react";
import { platforms } from "../../app/platforms";
import {
  acceptAccounts,
  qrLogin,
  refreshAccounts,
  updateAccount,
  useAccounts,
} from "../../stores/accountsStorage";
import type { AccountItem, AccountSite, QrSession } from "../../types/accounts";

const stateLabels: Record<AccountItem["state"], string> = {
  empty: "未登录", default: "默认访客", saved: "已保存",
  valid: "已登录", invalid: "已失效", unknown: "待校验",
};
export function AccountPage() {
  const { message, modal } = AntApp.useApp();
  const { data, error } = useAccounts();
  const [busy, setBusy] = useState("");
  const locked = useRef(false);
  const [editing, setEditing] = useState<AccountSite | null>(null);
  const [method, setMethod] = useState("qr");
  const [credential, setCredential] = useState("");
  const [qrVersion, setQrVersion] = useState(0);
  const [qr, setQr] = useState<QrSession | null>(null);
  const [qrState, setQrState] = useState("loading");
  const [qrError, setQrError] = useState("");
  const revision = useRef(data?.revision);
  revision.current = data?.revision;

  useEffect(() => {
    if (editing !== "bilibili" || method !== "qr") return;
    const controller = new AbortController();
    let session: QrSession | undefined;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let expiry: ReturnType<typeof setTimeout> | undefined;
    let done = false;
    setQr(null);
    setQrError("");
    setQrState("loading");
    const fail = (error: unknown) => {
      if (controller.signal.aborted) return;
      setQrState("error");
      setQrError(error instanceof Error ? error.message : "二维码登录失败");
      clearTimeout(timer);
      clearTimeout(expiry);
    };
    const poll = async () => {
      if (!session || controller.signal.aborted) return;
      try {
        const result = await qrLogin.poll(session.sessionId, controller.signal);
        if (controller.signal.aborted) return;
        setQrState(result.state);
        if (result.state === "success" && result.accounts) {
          done = true;
          clearTimeout(expiry);
          acceptAccounts(result.accounts);
          setEditing(null);
          void message.success("哔哩哔哩登录成功");
          void updateAccount("check", "bilibili", result.accounts.revision).catch(() => {
            void message.warning("账号已保存，暂时无法校验，请稍后重试");
          });
        } else if (result.state !== "expired") {
          timer = setTimeout(() => void poll(), 3000);
        } else {
          clearTimeout(expiry);
        }
      } catch (error) { fail(error); }
    };
    void (async () => {
      try {
        if (revision.current === undefined) throw new Error("请先读取账号数据");
        session = await qrLogin.generate(revision.current, controller.signal);
        if (controller.signal.aborted) return;
        setQr(session);
        setQrState("waiting");
        expiry = setTimeout(() => {
          setQrState("expired");
          clearTimeout(timer);
          controller.abort();
          if (session) void qrLogin.cancel(session.sessionId).catch(() => {});
        }, Math.max(0, session.expiresAt - Date.now()));
        timer = setTimeout(() => void poll(), 3000);
      } catch (error) { fail(error); }
    })();
    return () => {
      controller.abort();
      clearTimeout(timer);
      clearTimeout(expiry);
      if (session && !done) void qrLogin.cancel(session.sessionId).catch(() => {});
    };
  }, [editing, method, qrVersion, message]);

  async function run(key: string, action: () => Promise<unknown>) {
    if (locked.current) return;
    locked.current = true;
    setBusy(key);
    try { await action(); }
    catch (error) {
      void message.error(error instanceof Error ? error.message : "账号操作失败");
      await refreshAccounts().catch(() => {});
    } finally {
      locked.current = false;
      setBusy("");
    }
  }
  const close = () => { setEditing(null); setCredential(""); };
  const editingPlatform = platforms.find((item) => item.id === editing);
  return (
    <div className="settings-content account-content">
      <div className="section-heading">
        <h2>账号管理</h2>
        <Tooltip title="刷新账号状态">
          <Button icon={<RefreshCw size={17} />} loading={busy === "refresh"}
            disabled={!!busy} onClick={() => void run("refresh", async () => {
              await refreshAccounts();
              void message.success("账号状态已刷新");
            })} aria-label="刷新账号状态" />
        </Tooltip>
      </div>
      {error && <Alert type="error" showIcon message={error} />}
      {!data && !error && <div className="muted">正在读取账号</div>}
      <div className="account-list">
        {data?.items.map((item) => {
          const platform = platforms.find((value) => value.id === item.site);
          return (
            <div className="account-row" key={item.site}>
              <img className="account-platform-logo" src={`/assets/${platform?.logo}`} alt="" />
              <div className="account-profile">
                <strong>{platform?.name ?? item.site}</strong>
                <span className="muted">{item.name || item.message ||
                  (item.site === "huya" ? "无需登录" : item.site === "douyin" && item.configured ? "自定义 ttwid" : "")}</span>
              </div>
              <Tag color={item.state === "valid" ? "success" : item.state === "invalid" ? "error" : undefined}>
                {item.site === "huya" ? "无需登录" : stateLabels[item.state]}
              </Tag>
              {item.site !== "huya" && <div className="actions account-actions">
                {item.configured && item.site !== "douyin" &&
                  <Tooltip title="校验账号">
                    <Button icon={<RefreshCw size={16} />} aria-label="校验账号"
                      loading={busy === `check-${item.site}`} disabled={!!busy || !!error}
                      onClick={() => void run(`check-${item.site}`, () => updateAccount("check", item.site as AccountSite, data.revision))} />
                  </Tooltip>}
                <Tooltip title={item.configured ? "更新账号" : item.site === "douyin" ? "配置 ttwid" : "登录"}>
                  <Button icon={<LogIn size={16} />} aria-label="登录或更新账号" disabled={!!busy || !!error}
                    onClick={() => { setCredential(""); setMethod("qr"); setEditing(item.site as AccountSite); }} />
                </Tooltip>
                {item.configured && <Tooltip title={item.site === "douyin" ? "恢复默认访客" : "退出登录"}>
                  <Button danger icon={<LogOut size={16} />} aria-label="清除账号"
                    disabled={!!busy || !!error} loading={busy === `clear-${item.site}`}
                    onClick={() => void run(`clear-${item.site}`, async () => {
                      if (!(await modal.confirm({ title: `清除${platform?.name}账号？`, okButtonProps: { danger: true } }))) return;
                      await updateAccount("clear", item.site as AccountSite, data.revision);
                      void message.success("账号已清除");
                    })} />
                </Tooltip>}
              </div>}
            </div>
          );
        })}
      </div>
      <Modal open={editing !== null} title={`${editingPlatform?.name ?? ""}账号`}
        onCancel={close} closable={!busy} maskClosable={!busy} keyboard={!busy}
        footer={editing === "bilibili" && method === "qr" ? null : [
          <Button key="cancel" disabled={!!busy} onClick={close}>取消</Button>,
          <Button key="save" type="primary" icon={<UsersRound size={16} />}
            loading={busy === "save"} disabled={!credential.trim() || !!busy || !!error}
            onClick={() => void run("save", async () => {
              if (!editing || !data) return;
              await updateAccount("save", editing, data.revision, credential);
              close();
              void message.success("账号已保存");
            })}>保存</Button>,
        ]}>
        {editing === "bilibili" && <Tabs activeKey={method} onChange={setMethod}
          items={[{ key: "qr", label: "扫码登录", disabled: !!busy }, { key: "cookie", label: "Cookie 登录", disabled: !!busy }]} />}
        {editing === "bilibili" && method === "qr" ? (
          <div className="account-qr">
            <QRCode value={qr?.url || "https://passport.bilibili.com"} size={220}
              status={qrState === "loading" ? "loading" : ["error", "expired"].includes(qrState) ? "expired" : "active"}
              onRefresh={() => setQrVersion((value) => value + 1)} />
            <span className="muted">{qrError || ({
              loading: "正在获取二维码", waiting: "等待扫码", scanned: "已扫码，等待确认",
              expired: "二维码已过期",
            } as Record<string, string>)[qrState]}</span>
          </div>
        ) : (
          <Input.Password value={credential} maxLength={50000} autoComplete="off"
            disabled={!!busy} aria-label={editing === "douyu" ? "dy_auth" : editing === "douyin" ? "ttwid" : "Cookie"}
            placeholder={editing === "douyu" ? "dy_auth" : editing === "douyin" ? "ttwid" : "Cookie"}
            onChange={(event) => setCredential(event.target.value)} />
        )}
      </Modal>
    </div>
  );
}
