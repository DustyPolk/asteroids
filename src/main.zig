const std = @import("std");
const c = @cImport({
    @cInclude("raylib.h");
});

const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 600;
const SHIP_SIZE = 20;
const ROTATION_SPEED = 4.0;
const ACCELERATION = 0.2;
const MAX_SPEED = 5.0;
const FRICTION = 0.985;
const MAX_BULLETS = 5;
const BULLET_SPEED = 8.0;
const MAX_ASTEROIDS = 32;
const MIN_ASTEROID_SIZE = 20;
const MAX_ASTEROID_SIZE = 50;
const SPLIT_SIZE_THRESHOLD = 30;
const SPLIT_ANGLE: f32 = 0.785398;
const MAX_PARTICLES = 2000;
const PARTICLE_LIFETIME = 60; // frames
const EXPLOSION_PARTICLES = 60;
const THRUST_PARTICLES = 3;
const BULLET_TRAIL_PARTICLES = 2;
const GLOW_INTENSITY = 0.8;

const BACKGROUND_COLOR = c.Color{ .r = 10, .g = 10, .b = 20, .a = 255 };
const SHIP_COLOR = c.Color{ .r = 0, .g = 200, .b = 255, .a = 255 };
const THRUST_COLOR = c.Color{ .r = 255, .g = 100, .b = 0, .a = 255 };
const ASTEROID_COLOR = c.Color{ .r = 180, .g = 180, .b = 200, .a = 255 };
const BULLET_COLOR = c.Color{ .r = 255, .g = 50, .b = 50, .a = 255 };

const CROSSHAIR_SIZE = 8;
const CROSSHAIR_COLOR = c.Color{ .r = 255, .g = 255, .b = 255, .a = 180 };
const ROTATION_SMOOTHING = 0.2; // Lower = smoother rotation

// Screen shake constants
const SHAKE_DURATION = 12;
const SHAKE_INTENSITY = 8.0;
const SHAKE_FALLOFF = 0.85;

// Camera for screen shake
const Camera = struct {
    offset: c.Vector2,
    shake_time: i32,
    shake_intensity: f32,

    pub fn init() Camera {
        return Camera{
            .offset = c.Vector2{ .x = 0, .y = 0 },
            .shake_time = 0,
            .shake_intensity = 0,
        };
    }

    pub fn update(self: *Camera) void {
        if (self.shake_time > 0) {
            self.shake_time -= 1;
            const shake_x = @as(f32, @floatFromInt(c.GetRandomValue(-100, 100))) / 100.0 * self.shake_intensity;
            const shake_y = @as(f32, @floatFromInt(c.GetRandomValue(-100, 100))) / 100.0 * self.shake_intensity;
            self.offset = c.Vector2{ .x = shake_x, .y = shake_y };
            self.shake_intensity *= SHAKE_FALLOFF;
        } else {
            self.offset = c.Vector2{ .x = 0, .y = 0 };
            self.shake_intensity = 0;
        }
    }

    pub fn shake(self: *Camera, intensity: f32, options: Options) void {
        if (!options.screen_shake_enabled) return;
        self.shake_time = SHAKE_DURATION;
        self.shake_intensity = intensity;
    }

    pub fn getOffset(self: Camera) c.Vector2 {
        return self.offset;
    }
};

// Add viewport scaling
const Viewport = struct {
    width: i32,
    height: i32,
    scale: f32,

    pub fn init(width: i32, height: i32) Viewport {
        return Viewport{
            .width = width,
            .height = height,
            .scale = 1.0,
        };
    }

    pub fn updateScale(self: *Viewport, base_width: i32, base_height: i32) void {
        const scale_x = @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(base_width));
        const scale_y = @as(f32, @floatFromInt(self.height)) / @as(f32, @floatFromInt(base_height));
        self.scale = @min(scale_x, scale_y);
    }

    pub fn scaleValue(self: Viewport, value: f32) f32 {
        return value * self.scale;
    }
};

// Base resolution that we'll scale from
const BASE_WIDTH = 800;
const BASE_HEIGHT = 600;

const Resolution = struct {
    width: i32,
    height: i32,
    label: []const u8,
};

const AVAILABLE_RESOLUTIONS = [_]Resolution{
    .{ .width = 800, .height = 600, .label = "800x600" },
    .{ .width = 1024, .height = 768, .label = "1024x768" },
    .{ .width = 1280, .height = 720, .label = "1280x720 (720p)" },
    .{ .width = 1366, .height = 768, .label = "1366x768" },
    .{ .width = 1600, .height = 900, .label = "1600x900" },
    .{ .width = 1920, .height = 1080, .label = "1920x1080 (1080p)" },
};

const GameScreen = enum {
    Start,
    Game,
    Pause,
    Death,
    Options,
};

const Options = struct {
    screen_shake_enabled: bool,
    current_resolution: usize,
    selected_option: usize,
    resolution_menu_active: bool,

    pub fn init() Options {
        return Options{
            .screen_shake_enabled = true,
            .current_resolution = 0,
            .selected_option = 0,
            .resolution_menu_active = false,
        };
    }

    pub fn moveUp(self: *Options) void {
        if (self.resolution_menu_active) {
            if (self.current_resolution > 0) {
                self.current_resolution -= 1;
            }
        } else {
            if (self.selected_option > 0) {
                self.selected_option -= 1;
            }
        }
    }

    pub fn moveDown(self: *Options) void {
        if (self.resolution_menu_active) {
            if (self.current_resolution < AVAILABLE_RESOLUTIONS.len - 1) {
                self.current_resolution += 1;
            }
        } else {
            if (self.selected_option < 2) {
                self.selected_option += 1;
            }
        }
    }

    pub fn toggleOption(self: *Options, viewport: *Viewport) void {
        switch (self.selected_option) {
            0 => { // Resolution
                if (!self.resolution_menu_active) {
                    self.resolution_menu_active = true;
                } else {
                    self.resolution_menu_active = false;
                    // Apply resolution change
                    const new_res = AVAILABLE_RESOLUTIONS[self.current_resolution];
                    viewport.width = new_res.width;
                    viewport.height = new_res.height;
                    viewport.updateScale(BASE_WIDTH, BASE_HEIGHT);
                    c.SetWindowSize(new_res.width, new_res.height);
                    // Center window
                    const monitor = c.GetCurrentMonitor();
                    const monitor_width = c.GetMonitorWidth(monitor);
                    const monitor_height = c.GetMonitorHeight(monitor);
                    c.SetWindowPosition(@divTrunc(monitor_width - new_res.width, 2), @divTrunc(monitor_height - new_res.height, 2));
                }
            },
            1 => { // Screen Shake
                self.screen_shake_enabled = !self.screen_shake_enabled;
            },
            2 => {}, // Back
            else => {},
        }
    }

    pub fn draw(self: Options, viewport: Viewport) void {
        const title = "OPTIONS";
        const title_size = @as(i32, @intFromFloat(viewport.scaleValue(40)));
        const title_width = c.MeasureText(title.ptr, title_size);
        c.DrawText(title.ptr, @divTrunc(viewport.width - title_width, 2), @divTrunc(viewport.height, 3), title_size, c.WHITE);

        const text_size = @as(i32, @intFromFloat(viewport.scaleValue(20)));
        const base_y = @divTrunc(viewport.height, 3) + @as(i32, @intFromFloat(viewport.scaleValue(80)));
        const spacing = @as(i32, @intFromFloat(viewport.scaleValue(40)));

        // Resolution option
        const res_text = "Resolution: ";
        const res_value = AVAILABLE_RESOLUTIONS[self.current_resolution].label;
        const res_x = @divTrunc(viewport.width - c.MeasureText(res_text.ptr, text_size) - c.MeasureText(res_value.ptr, text_size), 2);

        if (self.resolution_menu_active) {
            // Draw resolution list
            var y = base_y;
            for (AVAILABLE_RESOLUTIONS, 0..) |res, i| {
                const is_selected = i == self.current_resolution;
                const x = @divTrunc(viewport.width - c.MeasureText(res.label.ptr, text_size), 2);

                if (is_selected) {
                    c.DrawText(">", x - 30, y, text_size, c.WHITE);
                    c.DrawText(res.label.ptr, x, y, text_size, c.GREEN);
                } else {
                    c.DrawText(res.label.ptr, x, y, text_size, c.GRAY);
                }
                y += spacing;
            }
            // Draw hint
            const hint = "Press ENTER/SPACE to select";
            const hint_width = c.MeasureText(hint.ptr, text_size);
            c.DrawText(hint.ptr, @divTrunc(viewport.width - hint_width, 2), y + spacing, text_size, c.GRAY);
        } else {
            if (self.selected_option == 0) {
                c.DrawText(">", res_x - 30, base_y, text_size, c.WHITE);
                c.DrawText(res_text.ptr, res_x, base_y, text_size, c.GREEN);
                c.DrawText(res_value.ptr, res_x + c.MeasureText(res_text.ptr, text_size), base_y, text_size, c.GREEN);
            } else {
                c.DrawText(res_text.ptr, res_x, base_y, text_size, c.GRAY);
                c.DrawText(res_value.ptr, res_x + c.MeasureText(res_text.ptr, text_size), base_y, text_size, c.GRAY);
            }

            // Screen shake option
            const shake_text = "Screen Shake: ";
            const shake_value = if (self.screen_shake_enabled) "ON" else "OFF";
            const shake_x = @divTrunc(viewport.width - c.MeasureText(shake_text.ptr, text_size) - c.MeasureText(shake_value.ptr, text_size), 2);
            if (self.selected_option == 1) {
                c.DrawText(">", shake_x - 30, base_y + spacing, text_size, c.WHITE);
                c.DrawText(shake_text.ptr, shake_x, base_y + spacing, text_size, c.GREEN);
                c.DrawText(shake_value.ptr, shake_x + c.MeasureText(shake_text.ptr, text_size), base_y + spacing, text_size, c.GREEN);
            } else {
                c.DrawText(shake_text.ptr, shake_x, base_y + spacing, text_size, c.GRAY);
                c.DrawText(shake_value.ptr, shake_x + c.MeasureText(shake_text.ptr, text_size), base_y + spacing, text_size, c.GRAY);
            }

            // Back option
            const back_text = "Back";
            const back_width = c.MeasureText(back_text.ptr, text_size);
            const back_x = @divTrunc(viewport.width - back_width, 2);
            if (self.selected_option == 2) {
                c.DrawText(">", back_x - 30, base_y + spacing * 2, text_size, c.WHITE);
                c.DrawText(back_text.ptr, back_x, base_y + spacing * 2, text_size, c.GREEN);
            } else {
                c.DrawText(back_text.ptr, back_x, base_y + spacing * 2, text_size, c.GRAY);
            }
        }
    }
};

const Menu = struct {
    selected_item: usize,
    items: []const []const u8,

    pub fn init(items: []const []const u8) Menu {
        return Menu{
            .selected_item = 0,
            .items = items,
        };
    }

    pub fn moveUp(self: *Menu) void {
        if (self.selected_item > 0) {
            self.selected_item -= 1;
        }
    }

    pub fn moveDown(self: *Menu) void {
        if (self.selected_item < self.items.len - 1) {
            self.selected_item += 1;
        }
    }

    pub fn draw(self: Menu, y_offset: i32, title: ?[]const u8, viewport: Viewport) void {
        const text_spacing = @as(i32, @intFromFloat(viewport.scaleValue(40)));
        var y_pos = y_offset;

        if (title) |t| {
            const title_size = @as(i32, @intFromFloat(viewport.scaleValue(40)));
            const title_width = c.MeasureText(t.ptr, title_size);
            c.DrawText(t.ptr, @divTrunc(viewport.width - title_width, 2), y_pos, title_size, c.WHITE);
            y_pos += @as(i32, @intFromFloat(viewport.scaleValue(80)));
        }

        for (self.items, 0..) |item, i| {
            const is_selected = i == self.selected_item;
            const text_size = @as(i32, @intFromFloat(viewport.scaleValue(20)));
            const text_width = c.MeasureText(item.ptr, text_size);
            const x = @divTrunc(viewport.width - text_width, 2);

            // Draw selection indicator
            if (is_selected) {
                c.DrawText(">", x - @as(i32, @intFromFloat(viewport.scaleValue(30))), y_pos, text_size, c.WHITE);
                c.DrawText(item.ptr, x, y_pos, text_size, c.GREEN);
            } else {
                c.DrawText(item.ptr, x, y_pos, text_size, c.GRAY);
            }
            y_pos += text_spacing;
        }
    }
};

const GameState = struct {
    score: u32,
    screen: GameScreen,
    previous_screen: GameScreen,
    respawn_timer: i32,
    options: Options,
    viewport: Viewport,
    start_menu: Menu,
    pause_menu: Menu,
    death_menu: Menu,

    pub fn init() GameState {
        return GameState{
            .score = 0,
            .screen = .Start,
            .previous_screen = .Start,
            .respawn_timer = 0,
            .options = Options.init(),
            .viewport = Viewport.init(BASE_WIDTH, BASE_HEIGHT),
            .start_menu = Menu.init(&[_][]const u8{ "Start Game", "Options", "Quit" }),
            .pause_menu = Menu.init(&[_][]const u8{ "Resume", "Options", "Return to Main Menu", "Quit" }),
            .death_menu = Menu.init(&[_][]const u8{ "Try Again", "Return to Main Menu", "Quit" }),
        };
    }

    pub fn reset(self: *GameState) void {
        self.score = 0;
        self.screen = .Game;
        self.previous_screen = .Start;
        self.respawn_timer = 120;
    }
};

const Bullet = struct {
    position: c.Vector2,
    velocity: c.Vector2,
    active: bool,

    pub fn init() Bullet {
        return Bullet{
            .position = c.Vector2{ .x = 0, .y = 0 },
            .velocity = c.Vector2{ .x = 0, .y = 0 },
            .active = false,
        };
    }

    pub fn update(self: *Bullet, particle_system: *ParticleSystem, viewport: Viewport) void {
        if (!self.active) return;

        // Spawn trail particles
        particle_system.spawnBulletTrail(self.position, self.velocity);

        self.position.x += self.velocity.x;
        self.position.y += self.velocity.y;

        // Deactivate if out of screen using viewport dimensions
        if (self.position.x < 0 or
            self.position.x > @as(f32, @floatFromInt(viewport.width)) or
            self.position.y < 0 or
            self.position.y > @as(f32, @floatFromInt(viewport.height)))
        {
            self.active = false;
        }
    }

    pub fn drawAt(self: Bullet, pos: c.Vector2) void {
        if (!self.active) return;
        c.DrawCircleV(pos, 3, BULLET_COLOR);
    }
};

const Asteroid = struct {
    position: c.Vector2,
    velocity: c.Vector2,
    size: f32,
    active: bool,

    pub fn init() Asteroid {
        return Asteroid{
            .position = c.Vector2{ .x = 0, .y = 0 },
            .velocity = c.Vector2{ .x = 0, .y = 0 },
            .size = 0,
            .active = false,
        };
    }

    pub fn spawn(self: *Asteroid, viewport: Viewport) void {
        const side = @mod(c.GetRandomValue(0, 3), 4);
        self.size = @as(f32, @floatFromInt(c.GetRandomValue(MIN_ASTEROID_SIZE, MAX_ASTEROID_SIZE)));

        switch (side) {
            0 => { // Top
                self.position.x = @as(f32, @floatFromInt(c.GetRandomValue(0, viewport.width)));
                self.position.y = -self.size;
            },
            1 => { // Right
                self.position.x = @as(f32, @floatFromInt(viewport.width)) + self.size;
                self.position.y = @as(f32, @floatFromInt(c.GetRandomValue(0, viewport.height)));
            },
            2 => { // Bottom
                self.position.x = @as(f32, @floatFromInt(c.GetRandomValue(0, viewport.width)));
                self.position.y = @as(f32, @floatFromInt(viewport.height)) + self.size;
            },
            else => { // Left
                self.position.x = -self.size;
                self.position.y = @as(f32, @floatFromInt(c.GetRandomValue(0, viewport.height)));
            },
        }

        // Random velocity
        const angle = @as(f32, @floatFromInt(c.GetRandomValue(0, 360))) * std.math.pi / 180.0;
        const speed = @as(f32, @floatFromInt(c.GetRandomValue(1, 3)));
        self.velocity = c.Vector2{
            .x = @cos(angle) * speed,
            .y = @sin(angle) * speed,
        };
        self.active = true;
    }

    pub fn update(self: *Asteroid, viewport: Viewport) void {
        if (!self.active) return;

        self.position.x += self.velocity.x;
        self.position.y += self.velocity.y;

        // Screen wrapping with viewport dimensions
        const width = @as(f32, @floatFromInt(viewport.width));
        const height = @as(f32, @floatFromInt(viewport.height));
        if (self.position.x < -self.size) self.position.x = width + self.size;
        if (self.position.x > width + self.size) self.position.x = -self.size;
        if (self.position.y < -self.size) self.position.y = height + self.size;
        if (self.position.y > height + self.size) self.position.y = -self.size;
    }

    pub fn drawAt(self: Asteroid, pos: c.Vector2) void {
        if (!self.active) return;
        c.DrawCircle(@as(c_int, @intFromFloat(pos.x)), @as(c_int, @intFromFloat(pos.y)), self.size, ASTEROID_COLOR);
        c.DrawCircleLines(@as(c_int, @intFromFloat(pos.x)), @as(c_int, @intFromFloat(pos.y)), self.size, c.WHITE);
    }

    pub fn split(self: *Asteroid, asteroids: []Asteroid) void {
        if (self.size < SPLIT_SIZE_THRESHOLD) return;

        const new_size = self.size * 0.6;
        var split_count: u32 = 0;

        // Try to spawn two smaller asteroids
        for (asteroids) |*new_asteroid| {
            if (!new_asteroid.active) {
                new_asteroid.active = true;
                new_asteroid.position = self.position;
                new_asteroid.size = new_size;

                // Calculate split velocities at angles +/- 45 degrees from original
                const base_angle = std.math.atan2(self.velocity.y, self.velocity.x);
                const split_angle = base_angle + if (split_count == 0) SPLIT_ANGLE else -SPLIT_ANGLE;
                const speed = @sqrt(self.velocity.x * self.velocity.x + self.velocity.y * self.velocity.y) * 1.2;

                new_asteroid.velocity = c.Vector2{
                    .x = @cos(split_angle) * speed,
                    .y = @sin(split_angle) * speed,
                };

                split_count += 1;
                if (split_count >= 2) break;
            }
        }
    }
};

const Particle = struct {
    position: c.Vector2,
    velocity: c.Vector2,
    color: c.Color,
    life: f32,
    active: bool,
    size: f32,
    glow: bool,

    pub fn init() Particle {
        return Particle{
            .position = c.Vector2{ .x = 0, .y = 0 },
            .velocity = c.Vector2{ .x = 0, .y = 0 },
            .color = c.WHITE,
            .life = 0,
            .active = false,
            .size = 1,
            .glow = false,
        };
    }

    pub fn update(self: *Particle) void {
        if (!self.active) return;

        self.position.x += self.velocity.x;
        self.position.y += self.velocity.y;
        self.life -= 1;

        if (self.life <= 0) {
            self.active = false;
            return;
        }

        // Fade out
        const alpha = @as(u8, @intFromFloat((self.life / PARTICLE_LIFETIME) * 255));
        self.color.a = alpha;
        self.size *= 0.97; // Slightly faster shrink
    }
};

const ParticleSystem = struct {
    particles: [MAX_PARTICLES]Particle,

    pub fn init() ParticleSystem {
        var system: ParticleSystem = undefined;
        for (&system.particles) |*particle| {
            particle.* = Particle.init();
        }
        return system;
    }

    pub fn update(self: *ParticleSystem) void {
        for (&self.particles) |*particle| {
            particle.update();
        }
    }

    pub fn draw(self: ParticleSystem, offset: c.Vector2) void {
        for (self.particles) |particle| {
            if (!particle.active) continue;

            // Draw glow effect
            if (particle.glow) {
                var glow_color = particle.color;
                glow_color.a = @as(u8, @intFromFloat(@as(f32, @floatFromInt(particle.color.a)) * GLOW_INTENSITY));
                const glow_pos = c.Vector2{
                    .x = particle.position.x + offset.x,
                    .y = particle.position.y + offset.y,
                };
                c.DrawCircleV(glow_pos, particle.size * 2.0, glow_color);
                c.DrawCircleV(glow_pos, particle.size * 1.5, glow_color);
            }

            const draw_pos = c.Vector2{
                .x = particle.position.x + offset.x,
                .y = particle.position.y + offset.y,
            };
            c.DrawCircleV(draw_pos, particle.size, particle.color);
        }
    }

    pub fn spawnExplosion(self: *ParticleSystem, position: c.Vector2, color: c.Color, size: f32) void {
        var i: u32 = 0;
        // Spawn main explosion particles
        while (i < EXPLOSION_PARTICLES) : (i += 1) {
            for (&self.particles) |*particle| {
                if (!particle.active) {
                    const angle = @as(f32, @floatFromInt(i)) * (std.math.pi * 2.0 / @as(f32, @floatFromInt(EXPLOSION_PARTICLES)));
                    const speed = @as(f32, @floatFromInt(c.GetRandomValue(3, 8)));
                    const spread = @as(f32, @floatFromInt(c.GetRandomValue(-20, 20))) * 0.1;

                    particle.* = Particle{
                        .position = position,
                        .velocity = c.Vector2{
                            .x = @cos(angle + spread) * speed,
                            .y = @sin(angle + spread) * speed,
                        },
                        .color = color,
                        .life = PARTICLE_LIFETIME,
                        .active = true,
                        .size = size * 0.3,
                        .glow = true,
                    };
                    break;
                }
            }
        }

        // Spawn additional debris particles
        i = 0;
        while (i < EXPLOSION_PARTICLES / 2) : (i += 1) {
            for (&self.particles) |*particle| {
                if (!particle.active) {
                    const angle = @as(f32, @floatFromInt(c.GetRandomValue(0, 360))) * std.math.pi / 180.0;
                    const speed = @as(f32, @floatFromInt(c.GetRandomValue(1, 4)));

                    particle.* = Particle{
                        .position = position,
                        .velocity = c.Vector2{
                            .x = @cos(angle) * speed,
                            .y = @sin(angle) * speed,
                        },
                        .color = c.WHITE,
                        .life = PARTICLE_LIFETIME * 0.7,
                        .active = true,
                        .size = size * 0.1,
                        .glow = false,
                    };
                    break;
                }
            }
        }
    }

    pub fn spawnThrustParticles(self: *ParticleSystem, position: c.Vector2, angle: f32) void {
        var i: u32 = 0;
        while (i < THRUST_PARTICLES) : (i += 1) {
            for (&self.particles) |*particle| {
                if (!particle.active) {
                    const spread = @as(f32, @floatFromInt(c.GetRandomValue(-30, 30))) * 0.02;
                    const speed = @as(f32, @floatFromInt(c.GetRandomValue(2, 4)));

                    particle.* = Particle{
                        .position = position,
                        .velocity = c.Vector2{
                            .x = @cos(angle + std.math.pi + spread) * speed,
                            .y = @sin(angle + std.math.pi + spread) * speed,
                        },
                        .color = THRUST_COLOR,
                        .life = PARTICLE_LIFETIME * 0.5,
                        .active = true,
                        .size = 2,
                        .glow = true,
                    };
                    break;
                }
            }
        }
    }

    pub fn spawnBulletTrail(self: *ParticleSystem, position: c.Vector2, velocity: c.Vector2) void {
        var i: u32 = 0;
        while (i < BULLET_TRAIL_PARTICLES) : (i += 1) {
            for (&self.particles) |*particle| {
                if (!particle.active) {
                    const spread = @as(f32, @floatFromInt(c.GetRandomValue(-10, 10))) * 0.02;

                    particle.* = Particle{
                        .position = position,
                        .velocity = c.Vector2{
                            .x = -velocity.x * 0.2 + spread,
                            .y = -velocity.y * 0.2 + spread,
                        },
                        .color = BULLET_COLOR,
                        .life = PARTICLE_LIFETIME * 0.3,
                        .active = true,
                        .size = 2,
                        .glow = true,
                    };
                    break;
                }
            }
        }
    }
};

const Player = struct {
    position: c.Vector2,
    velocity: c.Vector2,
    rotation: f32,
    target_rotation: f32, // New field for smooth rotation
    shoot_cooldown: i32,
    invincible: bool,
    thrusting: bool,

    pub fn init(viewport: Viewport) Player {
        return Player{
            .position = c.Vector2{ .x = @as(f32, @floatFromInt(viewport.width)) / 2, .y = @as(f32, @floatFromInt(viewport.height)) / 2 },
            .velocity = c.Vector2{ .x = 0, .y = 0 },
            .rotation = 0,
            .target_rotation = 0,
            .shoot_cooldown = 0,
            .invincible = true,
            .thrusting = false,
        };
    }

    pub fn reset(self: *Player, viewport: Viewport) void {
        self.position = c.Vector2{ .x = @as(f32, @floatFromInt(viewport.width)) / 2, .y = @as(f32, @floatFromInt(viewport.height)) / 2 };
        self.velocity = c.Vector2{ .x = 0, .y = 0 };
        self.rotation = 0;
        self.target_rotation = 0;
        self.shoot_cooldown = 0;
        self.invincible = true;
        self.thrusting = false;
    }

    pub fn update(self: *Player, viewport: Viewport) void {
        // Get mouse position and calculate angle to mouse
        const mouse_pos = c.GetMousePosition();
        const dx = mouse_pos.x - self.position.x;
        const dy = mouse_pos.y - self.position.y;
        self.target_rotation = std.math.atan2(dy, dx) * 180.0 / std.math.pi;

        // Smooth rotation
        var angle_diff = self.target_rotation - self.rotation;
        // Normalize angle to [-180, 180]
        while (angle_diff > 180.0) angle_diff -= 360.0;
        while (angle_diff < -180.0) angle_diff += 360.0;
        self.rotation += angle_diff * ROTATION_SMOOTHING;

        // Thrust with W key instead of up arrow
        self.thrusting = c.IsKeyDown(c.KEY_W);
        if (self.thrusting) {
            const angle = self.rotation * std.math.pi / 180.0;
            self.velocity.x += @cos(angle) * ACCELERATION;
            self.velocity.y += @sin(angle) * ACCELERATION;

            // Limit speed
            const speed = @sqrt(self.velocity.x * self.velocity.x + self.velocity.y * self.velocity.y);
            if (speed > MAX_SPEED) {
                const scale = MAX_SPEED / speed;
                self.velocity.x *= scale;
                self.velocity.y *= scale;
            }
        }

        // Update shooting cooldown
        if (self.shoot_cooldown > 0) self.shoot_cooldown -= 1;

        // Apply velocity and friction
        self.position.x += self.velocity.x;
        self.position.y += self.velocity.y;
        self.velocity.x *= FRICTION;
        self.velocity.y *= FRICTION;

        // Screen wrapping with viewport dimensions
        if (self.position.x < 0) self.position.x = @as(f32, @floatFromInt(viewport.width));
        if (self.position.x > @as(f32, @floatFromInt(viewport.width))) self.position.x = 0;
        if (self.position.y < 0) self.position.y = @as(f32, @floatFromInt(viewport.height));
        if (self.position.y > @as(f32, @floatFromInt(viewport.height))) self.position.y = 0;
    }

    pub fn shoot(self: *Player, bullets: []Bullet) void {
        if (self.shoot_cooldown > 0) return;

        // Find inactive bullet
        for (bullets) |*bullet| {
            if (!bullet.active) {
                const angle = self.rotation * std.math.pi / 180.0;
                bullet.position = self.position;
                bullet.velocity = c.Vector2{
                    .x = @cos(angle) * BULLET_SPEED,
                    .y = @sin(angle) * BULLET_SPEED,
                };
                bullet.active = true;
                self.shoot_cooldown = 10;
                break;
            }
        }
    }

    pub fn drawAt(self: Player, particle_system: *ParticleSystem, pos: c.Vector2) void {
        const angle = self.rotation * std.math.pi / 180.0;
        const cos = @cos(angle);
        const sin = @sin(angle);

        // Draw thrust flame and particles when thrusting
        if (self.thrusting) {
            const flame_v1 = c.Vector2{
                .x = pos.x - cos * SHIP_SIZE * 0.7,
                .y = pos.y - sin * SHIP_SIZE * 0.7,
            };
            const flame_v2 = c.Vector2{
                .x = pos.x + @cos(angle + 2.9) * SHIP_SIZE * 0.4,
                .y = pos.y + @sin(angle + 2.9) * SHIP_SIZE * 0.4,
            };
            const flame_v3 = c.Vector2{
                .x = pos.x + @cos(angle - 2.9) * SHIP_SIZE * 0.4,
                .y = pos.y + @sin(angle - 2.9) * SHIP_SIZE * 0.4,
            };
            c.DrawTriangle(flame_v1, flame_v2, flame_v3, THRUST_COLOR);

            // Spawn thrust particles
            particle_system.spawnThrustParticles(flame_v1, angle);
        }

        // Draw ship with modern style
        const v1 = c.Vector2{
            .x = pos.x + cos * SHIP_SIZE,
            .y = pos.y + sin * SHIP_SIZE,
        };
        const v2 = c.Vector2{
            .x = pos.x + @cos(angle + 2.6) * SHIP_SIZE * 0.7,
            .y = pos.y + @sin(angle + 2.6) * SHIP_SIZE * 0.7,
        };
        const v3 = c.Vector2{
            .x = pos.x + @cos(angle - 2.6) * SHIP_SIZE * 0.7,
            .y = pos.y + @sin(angle - 2.6) * SHIP_SIZE * 0.7,
        };

        // Flash when invincible with modern color
        const color = if (self.invincible and @mod(c.GetTime() * 10, 2) < 1)
            c.Color{ .r = 100, .g = 100, .b = 100, .a = 255 }
        else
            SHIP_COLOR;

        // Draw filled triangle with outline for modern look
        c.DrawTriangle(v1, v2, v3, color);
        c.DrawTriangleLines(v1, v2, v3, c.WHITE);

        // Draw crosshair at mouse position
        const mouse_pos = c.GetMousePosition();
        c.DrawLine(@as(c_int, @intFromFloat(mouse_pos.x - CROSSHAIR_SIZE)), @as(c_int, @intFromFloat(mouse_pos.y)), @as(c_int, @intFromFloat(mouse_pos.x + CROSSHAIR_SIZE)), @as(c_int, @intFromFloat(mouse_pos.y)), CROSSHAIR_COLOR);
        c.DrawLine(@as(c_int, @intFromFloat(mouse_pos.x)), @as(c_int, @intFromFloat(mouse_pos.y - CROSSHAIR_SIZE)), @as(c_int, @intFromFloat(mouse_pos.x)), @as(c_int, @intFromFloat(mouse_pos.y + CROSSHAIR_SIZE)), CROSSHAIR_COLOR);
    }
};

pub fn checkCollision(bullet: Bullet, asteroid: Asteroid) bool {
    if (!bullet.active or !asteroid.active) return false;
    const dx = bullet.position.x - asteroid.position.x;
    const dy = bullet.position.y - asteroid.position.y;
    const distance = @sqrt(dx * dx + dy * dy);
    return distance < asteroid.size;
}

pub fn checkPlayerAsteroidCollision(player: Player, asteroid: Asteroid) bool {
    if (!asteroid.active or player.invincible) return false;
    const dx = player.position.x - asteroid.position.x;
    const dy = player.position.y - asteroid.position.y;
    const distance = @sqrt(dx * dx + dy * dy);
    return distance < asteroid.size + SHIP_SIZE * 0.7;
}

pub fn main() !void {
    // Set window to not close with ESC
    c.SetExitKey(0);

    // Try to read saved resolution from a file
    var saved_resolution: usize = 0;
    if (std.fs.cwd().openFile("settings.dat", .{ .mode = .read_only })) |file| {
        var buffer: [8]u8 = undefined;
        if (file.read(&buffer)) |bytes_read| {
            if (bytes_read >= 1) {
                saved_resolution = @intCast(buffer[0]);
                if (saved_resolution >= AVAILABLE_RESOLUTIONS.len) {
                    saved_resolution = 0;
                }
            }
        } else |_| {}
        file.close();
    } else |_| {}

    // Initialize with saved resolution
    const initial_res = AVAILABLE_RESOLUTIONS[saved_resolution];
    c.InitWindow(initial_res.width, initial_res.height, "Asteroids");
    c.SetTargetFPS(60);
    c.HideCursor();

    var game_state = GameState.init();
    // Set the initial resolution in options
    game_state.options.current_resolution = saved_resolution;
    game_state.viewport.width = initial_res.width;
    game_state.viewport.height = initial_res.height;
    game_state.viewport.updateScale(BASE_WIDTH, BASE_HEIGHT);

    var player = Player.init(game_state.viewport);
    var bullets: [MAX_BULLETS]Bullet = undefined;
    var asteroids: [MAX_ASTEROIDS]Asteroid = undefined;
    var camera = Camera.init();
    var particle_system = ParticleSystem.init();

    // Initialize game objects
    for (&bullets) |*bullet| {
        bullet.* = Bullet.init();
    }
    for (&asteroids) |*asteroid| {
        asteroid.* = Asteroid.init();
    }

    main_loop: while (true) {
        // Check for window close button (X)
        if (c.WindowShouldClose()) {
            // Save current resolution before quitting
            if (std.fs.cwd().createFile("settings.dat", .{})) |file| {
                var buffer = [_]u8{@intCast(game_state.options.current_resolution)};
                _ = file.write(&buffer) catch {};
                file.close();
            } else |_| {}
            break;
        }

        switch (game_state.screen) {
            .Start => {
                if (c.IsKeyPressed(c.KEY_UP)) {
                    game_state.start_menu.moveUp();
                }
                if (c.IsKeyPressed(c.KEY_DOWN)) {
                    game_state.start_menu.moveDown();
                }
                if (c.IsKeyPressed(c.KEY_ENTER) or c.IsKeyPressed(c.KEY_SPACE)) {
                    switch (game_state.start_menu.selected_item) {
                        0 => { // Start Game
                            game_state.reset();
                            player.reset(game_state.viewport);
                            // Reset asteroids
                            for (&asteroids) |*asteroid| {
                                asteroid.active = false;
                            }
                            var initial_asteroids: u32 = 4;
                            for (&asteroids) |*asteroid| {
                                if (initial_asteroids > 0) {
                                    asteroid.spawn(game_state.viewport);
                                    initial_asteroids -= 1;
                                }
                            }
                        },
                        1 => { // Options
                            game_state.previous_screen = .Start;
                            game_state.screen = .Options;
                        },
                        2 => { // Quit
                            // Save current resolution before quitting
                            if (std.fs.cwd().createFile("settings.dat", .{})) |file| {
                                var buffer = [_]u8{@intCast(game_state.options.current_resolution)};
                                _ = file.write(&buffer) catch {};
                                file.close();
                            } else |_| {}
                            break :main_loop;
                        },
                        else => {},
                    }
                }

                // Draw start menu
                c.BeginDrawing();
                c.ClearBackground(BACKGROUND_COLOR);
                game_state.start_menu.draw(@divTrunc(game_state.viewport.height, 3), "ASTEROIDS", game_state.viewport);
                c.EndDrawing();
            },
            .Game => {
                // Handle P key for pause menu
                if (c.IsKeyPressed(c.KEY_P)) {
                    game_state.screen = .Pause;
                    // Draw the pause menu immediately
                    c.BeginDrawing();
                    c.ClearBackground(BACKGROUND_COLOR);
                    game_state.pause_menu.draw(@divTrunc(game_state.viewport.height, 3), "PAUSED", game_state.viewport);
                    c.EndDrawing();
                    continue;
                }

                // Regular game update
                player.update(game_state.viewport);

                if (c.IsMouseButtonPressed(c.MOUSE_BUTTON_LEFT)) {
                    player.shoot(&bullets);
                }

                // Update bullets and check collisions
                for (&bullets) |*bullet| {
                    bullet.update(&particle_system, game_state.viewport);

                    for (&asteroids) |*asteroid| {
                        if (checkCollision(bullet.*, asteroid.*)) {
                            bullet.active = false;

                            // Create explosion effect and screen shake
                            particle_system.spawnExplosion(asteroid.position, ASTEROID_COLOR, asteroid.size);
                            camera.shake(SHAKE_INTENSITY * (asteroid.size / MAX_ASTEROID_SIZE), game_state.options);

                            // Split or destroy asteroid
                            if (asteroid.size >= SPLIT_SIZE_THRESHOLD) {
                                asteroid.split(&asteroids);
                                game_state.score += 100;
                            } else {
                                game_state.score += 50;
                            }
                            asteroid.active = false;
                        }
                    }
                }

                // Update asteroids and check player collision
                for (&asteroids) |*asteroid| {
                    asteroid.update(game_state.viewport);

                    if (checkPlayerAsteroidCollision(player, asteroid.*)) {
                        game_state.screen = .Death;
                    }
                }

                // Spawn new asteroids if there are too few
                var active_count: u32 = 0;
                for (asteroids) |asteroid| {
                    if (asteroid.active) active_count += 1;
                }
                if (active_count < 4) {
                    for (&asteroids) |*asteroid| {
                        if (!asteroid.active) {
                            asteroid.spawn(game_state.viewport);
                            break;
                        }
                    }
                }

                // Update particles
                particle_system.update();

                // Update camera shake
                camera.update();

                // Draw
                c.BeginDrawing();
                c.ClearBackground(BACKGROUND_COLOR);

                // Apply camera shake offset to all drawing
                const offset = camera.getOffset();

                // Draw particles behind everything
                particle_system.draw(offset);

                // Draw game objects with offset
                const draw_pos = c.Vector2{
                    .x = player.position.x + offset.x,
                    .y = player.position.y + offset.y,
                };
                player.drawAt(&particle_system, draw_pos);

                for (bullets) |bullet| {
                    const bullet_pos = c.Vector2{
                        .x = bullet.position.x + offset.x,
                        .y = bullet.position.y + offset.y,
                    };
                    bullet.drawAt(bullet_pos);
                }

                for (asteroids) |asteroid| {
                    const asteroid_pos = c.Vector2{
                        .x = asteroid.position.x + offset.x,
                        .y = asteroid.position.y + offset.y,
                    };
                    asteroid.drawAt(asteroid_pos);
                }

                // Draw score
                const score_text = std.fmt.allocPrint(std.heap.page_allocator, "Score: {d}", .{game_state.score}) catch "Score: ERR";
                c.DrawText(@ptrCast(score_text), 10, 40, 20, c.GREEN);

                c.DrawFPS(10, 10);
                c.EndDrawing();
            },
            .Pause => {
                if (c.IsKeyPressed(c.KEY_UP)) {
                    game_state.pause_menu.moveUp();
                }
                if (c.IsKeyPressed(c.KEY_DOWN)) {
                    game_state.pause_menu.moveDown();
                }
                if (c.IsKeyPressed(c.KEY_ENTER) or c.IsKeyPressed(c.KEY_SPACE)) {
                    switch (game_state.pause_menu.selected_item) {
                        0 => game_state.screen = .Game, // Resume
                        1 => { // Options
                            game_state.previous_screen = .Pause;
                            game_state.screen = .Options;
                        },
                        2 => game_state.screen = .Start, // Return to Main Menu
                        3 => { // Quit
                            // Save current resolution before quitting
                            if (std.fs.cwd().createFile("settings.dat", .{})) |file| {
                                var buffer = [_]u8{@intCast(game_state.options.current_resolution)};
                                _ = file.write(&buffer) catch {};
                                file.close();
                            } else |_| {}
                            break :main_loop;
                        },
                        else => {},
                    }
                }
                // Handle P key to resume game
                if (c.IsKeyPressed(c.KEY_P)) {
                    game_state.screen = .Game;
                }

                // Draw pause menu
                c.BeginDrawing();
                c.ClearBackground(BACKGROUND_COLOR);
                game_state.pause_menu.draw(@divTrunc(game_state.viewport.height, 3), "PAUSED", game_state.viewport);
                c.EndDrawing();
            },
            .Death => {
                if (c.IsKeyPressed(c.KEY_UP)) {
                    game_state.death_menu.moveUp();
                }
                if (c.IsKeyPressed(c.KEY_DOWN)) {
                    game_state.death_menu.moveDown();
                }
                if (c.IsKeyPressed(c.KEY_ENTER) or c.IsKeyPressed(c.KEY_SPACE)) {
                    switch (game_state.death_menu.selected_item) {
                        0 => { // Try Again
                            game_state.reset();
                            player.reset(game_state.viewport);
                            // Reset asteroids
                            for (&asteroids) |*asteroid| {
                                asteroid.active = false;
                            }
                            var initial_asteroids: u32 = 4;
                            for (&asteroids) |*asteroid| {
                                if (initial_asteroids > 0) {
                                    asteroid.spawn(game_state.viewport);
                                    initial_asteroids -= 1;
                                }
                            }
                        },
                        1 => game_state.screen = .Start, // Return to Main Menu
                        2 => { // Quit
                            // Save current resolution before quitting
                            if (std.fs.cwd().createFile("settings.dat", .{})) |file| {
                                var buffer = [_]u8{@intCast(game_state.options.current_resolution)};
                                _ = file.write(&buffer) catch {};
                                file.close();
                            } else |_| {}
                            break :main_loop;
                        },
                        else => {},
                    }
                }

                // Draw death menu
                c.BeginDrawing();
                c.ClearBackground(BACKGROUND_COLOR);
                game_state.death_menu.draw(@divTrunc(game_state.viewport.height, 3), "GAME OVER", game_state.viewport);
                const score_text = std.fmt.allocPrint(std.heap.page_allocator, "Final Score: {d}", .{game_state.score}) catch "Score: ERR";
                const score_size = @as(i32, @intFromFloat(game_state.viewport.scaleValue(30)));
                const text_width = c.MeasureText(@ptrCast(score_text), score_size);
                c.DrawText(@ptrCast(score_text), @divTrunc(game_state.viewport.width - text_width, 2), @divTrunc(game_state.viewport.height, 3) + @as(i32, @intFromFloat(game_state.viewport.scaleValue(60))), score_size, c.GREEN);
                c.EndDrawing();
            },
            .Options => {
                if (c.IsKeyPressed(c.KEY_UP)) {
                    game_state.options.moveUp();
                }
                if (c.IsKeyPressed(c.KEY_DOWN)) {
                    game_state.options.moveDown();
                }
                if (c.IsKeyPressed(c.KEY_ENTER) or c.IsKeyPressed(c.KEY_SPACE)) {
                    if (game_state.options.selected_option == 2 and !game_state.options.resolution_menu_active) {
                        game_state.screen = game_state.previous_screen;
                    } else {
                        game_state.options.toggleOption(&game_state.viewport);
                    }
                }
                if (c.IsKeyPressed(c.KEY_ESCAPE)) {
                    if (game_state.options.resolution_menu_active) {
                        game_state.options.resolution_menu_active = false;
                    } else {
                        game_state.screen = game_state.previous_screen;
                    }
                }

                // Draw options menu
                c.BeginDrawing();
                c.ClearBackground(BACKGROUND_COLOR);
                game_state.options.draw(game_state.viewport);
                c.EndDrawing();
            },
        }
    }

    c.ShowCursor();
    c.CloseWindow();
}
