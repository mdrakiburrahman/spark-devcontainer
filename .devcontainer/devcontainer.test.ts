import { execSync } from 'child_process';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'fs';
import { join } from 'path';

describe('Devcontainer Integration Tests', () => {
  const timestamp = new Date().toISOString().replace(/[-:]/g, '').replace('T', '_').split('.')[0];
  const workspaceRoot = execSync('git rev-parse --show-toplevel').toString().trim();
  const devcontainerJson = join(workspaceRoot, '.devcontainer', 'devcontainer.json');
  const devcontainerImage = readFileSync(devcontainerJson, 'utf8').match(/"image":\s*"([^"]+)"/)?.[1];
  const workspaceDir = '/tmp/test-workspace';
  const logDir = join(workspaceRoot, 'logs', 'test-runs', timestamp);
  let containerId: string;

  if (!devcontainerImage) throw new Error('Could not read image from devcontainer.json');

  beforeAll(() => mkdirSync(logDir, { recursive: true }));

  afterAll(() => {
    if (containerId) execSync(`docker rm -f spark-devcontainer-test`, { stdio: 'pipe' });
    if (existsSync(workspaceDir)) rmSync(workspaceDir, { recursive: true, force: true });
  });

  test('Setup test workspace', () => {
    if (existsSync(workspaceDir)) rmSync(workspaceDir, { recursive: true, force: true });
    mkdirSync(workspaceDir, { recursive: true });
    
    execSync('git init -q', { cwd: workspaceDir });
    execSync('git config user.email "test@example.com"', { cwd: workspaceDir });
    execSync('git config user.name "Test User"', { cwd: workspaceDir });
    writeFileSync(join(workspaceDir, 'README.md'), '# Test\n');
    execSync('git add README.md && git commit -q -m "init"', { cwd: workspaceDir });
    writeFileSync(join(workspaceDir, 'package.json'), JSON.stringify({ name: 'test', version: '1.0.0', private: true }));
    
    expect(existsSync(join(workspaceDir, '.git'))).toBe(true);
  });

  test('Start and verify container', () => {
    const cmd = [
      'docker run -d --name spark-devcontainer-test --cap-add=SYS_ADMIN',
      '--device=/dev/fuse --security-opt=apparmor:unconfined',
      `-v ${workspaceDir}:/workspace -v /dev/fuse:/dev/fuse:rw`,
      '-w /workspace --user vscode',
      devcontainerImage,
      'sleep infinity'
    ].join(' ');
    
    containerId = execSync(cmd).toString().trim();
    writeFileSync(join(logDir, 'docker-run.log'), containerId);
    
    // Wait for container
    for (let i = 0; i < 30; i++) {
      const status = execSync('docker inspect spark-devcontainer-test --format="{{.State.Status}}"', { encoding: 'utf8' }).trim();
      if (status === 'running') break;
      execSync('sleep 1');
    }
    
    expect(containerId).toBeTruthy();
  });

  test('Run post-create commands', () => {
    const output = execSync(
      'docker exec spark-devcontainer-test bash -c "cd /workspace && /tmp/overlay/post-create-commands.sh"',
      { encoding: 'utf8' }
    );
    writeFileSync(join(logDir, 'post-create.log'), output);
    expect(output).toContain('Hatch');
  });

  test('Run post-attach commands', () => {
    const output = execSync(
      'docker exec spark-devcontainer-test bash -c "cd /workspace && /tmp/overlay/post-attach-commands.sh"',
      { encoding: 'utf8' }
    );
    writeFileSync(join(logDir, 'post-attach.log'), output);
    expect(output).toContain('SPARK DEVCONTAINER READY');
  });

  test('Spark Shell SELECT 1', () => {
    const output = execSync(
      'docker exec spark-devcontainer-test bash -c \'echo "spark.sql(\\"SELECT 1\\").show()" | /opt/spark/bin/spark-shell --master local[1] 2>&1\'',
      { encoding: 'utf8' }
    );
    writeFileSync(join(logDir, 'spark-shell.log'), output);
    expect(output).toContain('|  1|');
  });

  test('Livy health check', () => {
    let healthy = false;
    for (let i = 0; i < 30; i++) {
      try {
        const output = execSync('docker exec spark-devcontainer-test curl -s http://localhost:8998/sessions', { encoding: 'utf8' });
        if (output.includes('sessions')) {
          writeFileSync(join(logDir, 'livy-health.log'), output);
          healthy = true;
          break;
        }
      } catch (e) { }
      execSync('sleep 1');
    }
    expect(healthy).toBe(true);
  });
});

