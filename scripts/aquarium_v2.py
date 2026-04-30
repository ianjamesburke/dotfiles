#!/usr/bin/env python3

import argparse
import curses
import math
import random
import time
from dataclasses import dataclass
from typing import List, Optional, Sequence, Tuple


COLOR_WATER = 1
COLOR_SAND = 2
COLOR_PLANT = 3
COLOR_BUBBLE = 4
COLOR_FOOD = 5
COLOR_GOLD = 6
COLOR_NEON = 7
COLOR_CORAL = 8
COLOR_SILVER = 9
COLOR_BARRACUDA = 10


MIRROR_MAP = str.maketrans(
    {
        "<": ">",
        ">": "<",
        "/": "\\",
        "\\": "/",
        "(": ")",
        ")": "(",
        "[": "]",
        "]": "[",
        "{": "}",
        "}": "{",
    }
)


def clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(upper, value))


def mirror_line(line: str) -> str:
    return line.translate(MIRROR_MAP)[::-1]


def prepare_frames(frames_right: Sequence[Sequence[str]]) -> Tuple[List[List[str]], List[List[str]]]:
    max_height = max(len(frame) for frame in frames_right)
    max_width = max(len(line) for frame in frames_right for line in frame)

    padded_right: List[List[str]] = []
    padded_left: List[List[str]] = []
    blank = " " * max_width

    for frame in frames_right:
        right_lines = [line.ljust(max_width) for line in frame]
        while len(right_lines) < max_height:
            right_lines.append(blank)
        left_lines = [mirror_line(line).ljust(max_width) for line in right_lines]
        padded_right.append(right_lines)
        padded_left.append(left_lines)

    return padded_right, padded_left


@dataclass(frozen=True)
class Species:
    name: str
    color_pair: int
    base_speed: float
    schooling: float
    appetite: float
    frames_right: Sequence[Sequence[str]]


MINNOW_RIGHT = [
    [" ><º>"],
    [" ><º>"],
]

KOI_RIGHT = [
    [" ><((º> "],
    [" ><>((º>"],
]

CATFISH_RIGHT = [
    [" ><{{{º> "],
    [" ><>{{º> "],
]

ANGEL_RIGHT = [
    [" <\\º> "],
    [" <\\º> "],
]


BARRACUDA_RIGHT = [
    ["}>===º>"],
    [" }>==º>"],
]


SPECIES_LIBRARY = [
    Species("minnow", COLOR_NEON, 12.0, 1.30, 1.20, MINNOW_RIGHT),
    Species("koi", COLOR_GOLD, 8.0, 0.85, 1.00, KOI_RIGHT),
    Species("catfish", COLOR_SILVER, 6.6, 0.75, 1.30, CATFISH_RIGHT),
    Species("angel", COLOR_CORAL, 5.6, 0.65, 0.90, ANGEL_RIGHT),
]


class Canvas:
    def __init__(self, stdscr: curses.window):
        self.stdscr = stdscr

    def addstr(self, y: int, x: int, text: str, attr: int = 0):
        max_y, max_x = self.stdscr.getmaxyx()
        if y < 0 or y >= max_y or not text:
            return
        if x >= max_x or x + len(text) <= 0:
            return

        clipped = text
        draw_x = x
        if draw_x < 0:
            clipped = clipped[-draw_x :]
            draw_x = 0
        if draw_x + len(clipped) > max_x:
            clipped = clipped[: max_x - draw_x]
        if not clipped:
            return

        try:
            self.stdscr.addstr(y, draw_x, clipped, attr)
        except curses.error:
            pass

    def addch(self, y: int, x: int, ch: str, attr: int = 0):
        if not ch:
            return
        self.addstr(y, x, ch[0], attr)


class Bubble:
    def __init__(self, x: float, y: float):
        self.x = x
        self.y = y
        self.dx = random.uniform(-0.35, 0.35)
        self.dy = random.uniform(-6.0, -3.0)
        self.char = random.choice(["o", "O", "."])
        self.life = random.uniform(5.0, 10.0)

    def update(self, dt: float):
        self.life -= dt
        self.x += (self.dx + math.sin(self.y * 0.7 + time.time() * 3.0) * 0.12) * dt
        self.y += self.dy * dt

    def draw(self, canvas: Canvas):
        canvas.addch(int(self.y), int(self.x), self.char, curses.color_pair(COLOR_BUBBLE))


class Food:
    def __init__(self, x: float, y: float):
        self.x = x
        self.y = y
        self.dy = random.uniform(2.5, 4.0)
        self.consumed = False

    def update(self, dt: float, floor_y: int):
        self.y += self.dy * dt
        if self.y >= floor_y:
            self.y = float(floor_y)
            self.dy = 0.0

    def draw(self, canvas: Canvas):
        canvas.addch(int(self.y), int(self.x), "*", curses.color_pair(COLOR_FOOD))


class Plant:
    def __init__(self, x: int, floor_y: int, style: str):
        self.x = x
        self.floor_y = floor_y
        self.style = style
        self.height = random.randint(3, 8)
        self.offset = random.uniform(0.0, math.tau)
        self.speed = random.uniform(0.5, 1.4)

    def draw(self, canvas: Canvas, total_time: float):
        attr = curses.color_pair(COLOR_PLANT)
        if self.style == "kelp":
            for step in range(self.height):
                sway = int(math.sin(total_time * self.speed + step * 0.45 + self.offset) * 1.4)
                ch = "|" if step % 2 == 0 else "/"
                canvas.addch(self.floor_y - step, self.x + sway, ch, attr)
        elif self.style == "coral":
            for step in range(max(2, self.height // 2)):
                y = self.floor_y - step
                canvas.addch(y, self.x, "Y", curses.color_pair(COLOR_CORAL))
                if step > 0:
                    canvas.addch(y, self.x - 1, "/", curses.color_pair(COLOR_CORAL))
                    canvas.addch(y, self.x + 1, "\\", curses.color_pair(COLOR_CORAL))
        else:
            for step in range(self.height):
                sway = int(math.sin(total_time * self.speed * 0.8 + step * 0.35 + self.offset) * 1.0)
                ch = "{" if (step + int(total_time * 3.0)) % 2 == 0 else "}"
                canvas.addch(self.floor_y - step, self.x + sway, ch, attr)


class Fish:
    def __init__(self, width: int, height: int):
        self.species = random.choice(SPECIES_LIBRARY)
        self.frames_right, self.frames_left = prepare_frames(self.species.frames_right)
        self.height = len(self.frames_right[0])
        self.width = len(self.frames_right[0][0])

        self.depth = random.uniform(0.75, 1.25)
        self.lane = random.uniform(0.16, 0.82)
        self.x = random.uniform(2, max(3, width - self.width - 2))
        self.y = random.uniform(3, max(4, height - self.height - 4))
        self.face_right = random.choice([True, False])

        self.cruise_speed = self.species.base_speed * self.depth * random.uniform(0.88, 1.20)
        self.dx = self.cruise_speed if self.face_right else -self.cruise_speed
        self.dy = random.uniform(-0.4, 0.4)
        self.wiggle = random.uniform(0.0, math.tau)
        self.turn_lock = random.uniform(0.0, 1.5)
        self.dart_time = 0.0
        self.hunger = random.uniform(0.0, 1.0)
        self.animation_timer = 0.0
        self.frame_index = random.randrange(len(self.frames_right))
        self.peck_cooldown = 0.0

    def _attr(self) -> int:
        attr = curses.color_pair(self.species.color_pair)
        if self.depth < 0.9:
            attr |= curses.A_DIM
        elif self.depth > 1.12:
            attr |= curses.A_BOLD
        return attr

    def _frames(self) -> Sequence[Sequence[str]]:
        return self.frames_right if self.face_right else self.frames_left

    def choose_direction(self, want_right: bool):
        if self.face_right != want_right:
            self.face_right = want_right
            self.turn_lock = random.uniform(0.5, 1.8)

    def update(self, world: "World", dt: float):
        self.wiggle += dt * random.uniform(0.8, 1.4)
        self.turn_lock = max(0.0, self.turn_lock - dt)
        self.dart_time = max(0.0, self.dart_time - dt)
        self.hunger += dt * self.species.appetite * 0.05
        self.peck_cooldown = max(0.0, self.peck_cooldown - dt)

        swim_top = 2
        swim_bottom = max(swim_top + 2, world.floor_y - self.height - 1)
        lane_center = swim_top + self.lane * max(1, swim_bottom - swim_top)
        lane_center += math.sin(world.total_time * (0.7 + self.depth * 0.25) + self.wiggle) * 1.8

        if random.random() < dt * 0.08:
            self.dart_time = random.uniform(0.35, 0.9)

        target_food = self._nearest_food(world.foods)
        desired_forward = self.cruise_speed * (1.6 if self.dart_time > 0 else 1.0)
        desired_dx = desired_forward if self.face_right else -desired_forward
        desired_dy = clamp((lane_center - self.y) * 1.25, -2.2, 2.2)

        if world.currents:
            desired_dx += math.sin(world.total_time * 0.7 + self.y * 0.13) * 1.1
            desired_dy += math.cos(world.total_time * 0.9 + self.x * 0.08) * 0.35

        if target_food is not None and self.hunger > 0.35:
            if target_food.x > self.x + 1 and self.turn_lock <= 0:
                self.choose_direction(True)
            elif target_food.x < self.x - 1 and self.turn_lock <= 0:
                self.choose_direction(False)

            dx_food = target_food.x - self.x
            dy_food = target_food.y - self.y
            distance = math.hypot(dx_food, dy_food) or 1.0
            desired_dx += clamp(dx_food / distance, -1.0, 1.0) * 4.0
            desired_dy += clamp(dy_food / distance, -1.0, 1.0) * 2.5

            mouth_x = self.x + (self.width - 1 if self.face_right else 0)
            if abs(mouth_x - target_food.x) < 2.2 and abs(self.y - target_food.y) < 1.3:
                target_food.consumed = True
                self.hunger = 0.0

        # Mouse flee: scatter when mouse moves quickly
        if world.mouse_x is not None and world.mouse_y is not None and world.mouse_speed > 6.0:
            fdx = self.x - world.mouse_x
            fdy = self.y - world.mouse_y
            dist = math.hypot(fdx, fdy) or 1.0
            if dist < 22.0:
                strength = clamp((22.0 - dist) / 22.0, 0.0, 1.0) * clamp(world.mouse_speed / 15.0, 0.4, 2.0)
                desired_dx += (fdx / dist) * 9.0 * strength
                desired_dy += (fdy / dist) * 4.0 * strength
                if fdx < 0 and self.turn_lock <= 0:
                    self.choose_direction(False)
                elif fdx > 0 and self.turn_lock <= 0:
                    self.choose_direction(True)
        # Mouse peck: investigate cursor when it's been still for a while
        elif (world.mouse_x is not None and world.mouse_y is not None and
              world.mouse_still_time > 3.0 and
              world.mouse_speed < 1.5 and
              self.peck_cooldown <= 0 and
              target_food is None):
            pdx = world.mouse_x - self.x
            pdy = world.mouse_y - self.y
            dist = math.hypot(pdx, pdy) or 1.0
            if dist < 22.0:
                if pdx > 1.0 and self.turn_lock <= 0:
                    self.choose_direction(True)
                elif pdx < -1.0 and self.turn_lock <= 0:
                    self.choose_direction(False)
                desired_dx += clamp(pdx / dist, -1.0, 1.0) * 3.5
                desired_dy += clamp(pdy / dist, -1.0, 1.0) * 2.0
                mouth_x = self.x + (self.width - 1 if self.face_right else 0)
                if abs(mouth_x - world.mouse_x) < 2.5 and abs(self.y - world.mouse_y) < 1.5:
                    world.bubbles.append(Bubble(self.x + random.uniform(-0.5, 0.5), self.y))
                    self.dart_time = 0.4
                    self.peck_cooldown = 3.0
                    world.mouse_still_time = 1.5

        align_x, align_y, center_x, center_y, neighbors = 0.0, 0.0, 0.0, 0.0, 0
        for other in world.fishes:
            if other is self:
                continue
            dx = other.x - self.x
            dy = other.y - self.y
            distance = math.hypot(dx, dy)
            if distance < 14:
                align_x += other.dx
                align_y += other.dy
                center_x += other.x
                center_y += other.y
                neighbors += 1
            if distance and distance < max(self.width, other.width) + 1.5:
                push = (max(self.width, other.width) + 1.5 - distance) * 2.0
                desired_dx -= (dx / distance) * push
                desired_dy -= (dy / distance) * push * 0.6

        if neighbors:
            align_x /= neighbors
            align_y /= neighbors
            center_x /= neighbors
            center_y /= neighbors
            weight = self.species.schooling
            desired_dx += (align_x - self.dx) * 0.05 * weight
            desired_dy += (align_y - self.dy) * 0.08 * weight
            desired_dx += clamp(center_x - self.x, -4.0, 4.0) * 0.06 * weight
            desired_dy += clamp(center_y - self.y, -3.0, 3.0) * 0.12 * weight

        if self.x < 3 and self.turn_lock <= 0:
            self.choose_direction(True)
        elif self.x > world.width - self.width - 3 and self.turn_lock <= 0:
            self.choose_direction(False)

        if self.y < swim_top:
            desired_dy = max(desired_dy, 1.5)
        elif self.y > swim_bottom:
            desired_dy = min(desired_dy, -1.5)

        self.dx += (desired_dx - self.dx) * min(1.0, dt * 2.3)
        self.dy += (desired_dy - self.dy) * min(1.0, dt * 3.2)
        self.dx = clamp(self.dx, -14.0, 14.0)
        self.dy = clamp(self.dy, -3.5, 3.5)
        self.x += self.dx * dt
        self.y += self.dy * dt

        self.x = clamp(self.x, 1.0, max(1.0, world.width - self.width - 1.0))
        self.y = clamp(self.y, 1.0, max(1.0, world.floor_y - self.height))

        self.animation_timer += dt
        frame_delay = clamp(0.22 - abs(self.dx) * 0.008, 0.08, 0.24)
        if self.animation_timer >= frame_delay:
            self.animation_timer = 0.0
            self.frame_index = (self.frame_index + 1) % len(self.frames_right)

    def _nearest_food(self, foods: Sequence[Food]) -> Optional[Food]:
        best_food = None
        best_distance = 9999.0
        for food in foods:
            if food.consumed:
                continue
            distance = abs(food.x - self.x) + abs(food.y - self.y)
            if distance < best_distance:
                best_food = food
                best_distance = distance
        return best_food if best_distance < 40 else None

    def draw(self, canvas: Canvas):
        attr = self._attr()
        sprite = self._frames()[self.frame_index]
        base_y = int(self.y)
        base_x = int(self.x)
        for row, line in enumerate(sprite):
            canvas.addstr(base_y + row, base_x, line, attr)


class Barracuda:
    def __init__(self, width: int, floor_y: int):
        self.frames_right, self.frames_left = prepare_frames(BARRACUDA_RIGHT)
        self.sprite_height = len(self.frames_right[0])
        self.sprite_width = len(self.frames_right[0][0])
        self.face_right = random.choice([True, False])
        if self.face_right:
            self.x = -float(self.sprite_width + 2)
        else:
            self.x = float(width + 2)
        self.y = random.uniform(3.0, max(4.0, floor_y - self.sprite_height - 2))
        self.dx = 20.0 if self.face_right else -20.0
        self.dy = 0.0
        self.frame_index = 0
        self.animation_timer = 0.0
        self.leaving = False
        self.kills = 0

    def update(self, world: "World", dt: float):
        target: Optional[Fish] = None
        if not self.leaving and world.fishes:
            best_dist = 9999.0
            for fish in world.fishes:
                d = math.hypot(fish.x - self.x, fish.y - self.y)
                if d < best_dist:
                    best_dist = d
                    target = fish

        if target is not None and not self.leaving:
            dx = target.x - self.x
            dy = target.y - self.y
            dist = math.hypot(dx, dy) or 1.0
            speed = 22.0
            self.dx += (dx / dist * speed - self.dx) * min(1.0, dt * 1.8)
            self.dy += (dy / dist * speed - self.dy) * min(1.0, dt * 2.5)
            self.face_right = self.dx >= 0

            mouth_x = self.x + (self.sprite_width if self.face_right else 0)
            if math.hypot(mouth_x - target.x, self.y - target.y) < 3.0:
                world.fishes.remove(target)
                for _ in range(random.randint(4, 7)):
                    world.bubbles.append(Bubble(
                        target.x + random.uniform(-1.0, 1.0),
                        target.y + random.uniform(-0.5, 0.5),
                    ))
                self.kills += 1
                if self.kills >= 3 or not world.fishes:
                    self.leaving = True
        else:
            self.leaving = True
            exit_speed = 24.0 if self.face_right else -24.0
            self.dx += (exit_speed - self.dx) * min(1.0, dt * 2.0)
            self.dy += (0.0 - self.dy) * min(1.0, dt * 2.0)

        self.x += self.dx * dt
        self.y += self.dy * dt
        self.y = clamp(self.y, 1.0, max(1.0, world.floor_y - self.sprite_height))

        self.animation_timer += dt
        if self.animation_timer >= 0.09:
            self.animation_timer = 0.0
            self.frame_index = (self.frame_index + 1) % len(self.frames_right)

    def is_gone(self, world: "World") -> bool:
        return self.x < -self.sprite_width - 5 or self.x > world.width + 5

    def draw(self, canvas: Canvas):
        attr = curses.color_pair(COLOR_BARRACUDA) | curses.A_BOLD
        frames = self.frames_right if self.face_right else self.frames_left
        sprite = frames[self.frame_index]
        for row, line in enumerate(sprite):
            canvas.addstr(int(self.y) + row, int(self.x), line, attr)


class World:
    def __init__(self, width: int, height: int, initial_fish: int, countdown_seconds: Optional[float] = None):
        self.width = width
        self.height = height
        self.floor_y = max(3, height - 3)
        self.total_time = 0.0
        self.paused = False
        self.currents = True
        self.show_help = True
        self.show_hud = True
        self.bubbles: List[Bubble] = []
        self.foods: List[Food] = []
        self.fishes: List[Fish] = [Fish(width, height) for _ in range(initial_fish)]
        self.countdown_total = countdown_seconds if countdown_seconds and countdown_seconds > 0 else None
        self.countdown_remaining = self.countdown_total or 0.0
        self.depletion_accumulator = 0.0
        self.barracuda: Optional[Barracuda] = None
        self.vents = self._build_vents()
        self.plants = self._build_plants()
        self.mouse_x: Optional[float] = None
        self.mouse_y: Optional[float] = None
        self.mouse_speed = 0.0
        self.mouse_still_time = 0.0
        self._last_mouse_time = 0.0

    def _build_vents(self) -> List[int]:
        if self.width < 24:
            return [max(3, self.width // 2)]
        vents = [max(4, self.width // 5), max(7, self.width // 2), max(10, self.width - self.width // 5)]
        return sorted({clamp_int(v, 3, max(3, self.width - 4)) for v in vents})

    def _build_plants(self) -> List[Plant]:
        plants: List[Plant] = []
        styles = ["kelp", "seaweed", "coral"]
        for x in range(4, max(5, self.width - 4), 8):
            plants.append(Plant(x, self.floor_y, random.choice(styles)))
        return plants

    def resize(self, width: int, height: int):
        self.width = width
        self.height = height
        self.floor_y = max(3, height - 3)
        self.vents = self._build_vents()
        self.plants = self._build_plants()
        for fish in self.fishes:
            fish.x = clamp(fish.x, 1.0, max(1.0, self.width - fish.width - 1.0))
            fish.y = clamp(fish.y, 1.0, max(1.0, self.floor_y - fish.height))
        for food in self.foods:
            food.x = clamp(food.x, 2.0, max(2.0, self.width - 3.0))
            food.y = clamp(food.y, 1.0, float(self.floor_y))
        for bubble in self.bubbles:
            bubble.x = clamp(bubble.x, 1.0, max(1.0, self.width - 2.0))
            bubble.y = clamp(bubble.y, 1.0, float(self.floor_y))

    def add_fish(self):
        self.fishes.append(Fish(self.width, self.height))

    def remove_fish(self):
        if self.fishes:
            self.fishes.pop()

    def _expire_one_fish(self):
        if not self.fishes:
            return
        fish = self.fishes.pop(random.randrange(len(self.fishes)))
        for _ in range(random.randint(3, 6)):
            self.bubbles.append(Bubble(fish.x + random.uniform(-0.8, 0.8), fish.y + random.uniform(-0.4, 0.4)))

    def summon_barracuda(self):
        if self.barracuda is None:
            self.barracuda = Barracuda(self.width, self.floor_y)

    def drop_food(self):
        if self.mouse_x is not None:
            spawn_x = clamp(self.mouse_x, 2.0, max(2.0, self.width - 3.0))
            spawn_y = clamp(self.mouse_y if self.mouse_y is not None else 2.0, 1.0, float(self.floor_y - 1))
        else:
            spawn_x = random.uniform(3.0, max(4.0, self.width - 4.0))
            spawn_y = 2.0
        self.foods.append(Food(spawn_x, spawn_y))

    def on_mouse_move(self, x: float, y: float):
        now = time.time()
        if self.mouse_x is not None and self.mouse_y is not None:
            dt = max(0.001, now - self._last_mouse_time)
            dist = math.hypot(x - self.mouse_x, y - self.mouse_y)
            self.mouse_speed = dist / dt
            if dist > 0.5:
                self.mouse_still_time = 0.0
        self.mouse_x = x
        self.mouse_y = y
        self._last_mouse_time = now

    def bubble_burst(self):
        for vent_x in self.vents:
            for _ in range(random.randint(2, 5)):
                self.bubbles.append(Bubble(vent_x + random.uniform(-1.2, 1.2), self.floor_y - 1.0))

    def update(self, dt: float):
        self.total_time += dt
        self.mouse_speed = max(0.0, self.mouse_speed - dt * 12.0)
        if self.mouse_x is not None and self.mouse_speed < 1.5:
            self.mouse_still_time += dt
        if self.paused:
            return

        if self.countdown_total is not None:
            self.countdown_remaining = max(0.0, self.countdown_remaining - dt)
            if self.countdown_remaining <= 0.0 and self.fishes:
                self.depletion_accumulator += dt
                while self.depletion_accumulator >= 0.55 and self.fishes:
                    self.depletion_accumulator -= 0.55
                    self._expire_one_fish()

        vent_rate = 0.6 if self.currents else 0.4
        for vent_x in self.vents:
            if random.random() < dt * vent_rate:
                self.bubbles.append(Bubble(vent_x + random.uniform(-0.7, 0.7), self.floor_y - 1.0))

        if random.random() < dt * 0.15:
            self.bubbles.append(Bubble(random.uniform(2.0, max(3.0, self.width - 3.0)), self.floor_y - 1.0))

        for bubble in self.bubbles[:]:
            bubble.update(dt)
            if bubble.life <= 0 or bubble.y < 1:
                self.bubbles.remove(bubble)

        for food in self.foods[:]:
            food.update(dt, self.floor_y)
            if food.consumed:
                self.foods.remove(food)

        for fish in self.fishes:
            fish.update(self, dt)

        if self.barracuda is not None:
            self.barracuda.update(self, dt)
            if self.barracuda.is_gone(self):
                self.barracuda = None

    def draw(self, canvas: Canvas):
        self._draw_water(canvas)
        self._draw_light_shafts(canvas)
        for plant in self.plants:
            plant.draw(canvas, self.total_time)
        self._draw_decor(canvas)
        for food in self.foods:
            food.draw(canvas)
        for bubble in self.bubbles:
            bubble.draw(canvas)
        for fish in sorted(self.fishes, key=lambda item: (item.depth, item.y)):
            fish.draw(canvas)
        if self.barracuda is not None:
            self.barracuda.draw(canvas)
        self._draw_sand(canvas)

    def _draw_water(self, canvas: Canvas):
        water_attr = curses.color_pair(COLOR_WATER)
        shimmer_attr = curses.color_pair(COLOR_WATER) | curses.A_DIM
        for y in range(1, max(1, self.floor_y - 1)):
            for x in range(1, self.width - 1):
                char = " "
                phase = x * 0.17 + y * 0.63 + self.total_time * 2.2
                if int(phase * 10) % 37 == 0:
                    char = "."
                elif int((phase + 1.8) * 8) % 53 == 0:
                    char = "`"
                if char != " ":
                    canvas.addch(y, x, char, shimmer_attr)

            wave = "~" if y % 4 == 0 else " "
            if wave != " ":
                start = int((self.total_time * 4.0 + y * 3) % max(6, self.width - 6))
                canvas.addstr(y, start, "~ ~", water_attr | curses.A_DIM)

    def _draw_light_shafts(self, canvas: Canvas):
        attr = curses.color_pair(COLOR_BUBBLE) | curses.A_DIM
        for base_x in range(6, self.width - 4, 18):
            x = int(base_x + math.sin(self.total_time * 0.7 + base_x) * 2.0)
            for y in range(1, max(2, self.floor_y - 4)):
                if (y + x) % 3 == 0:
                    canvas.addch(y, x, ".", attr)

    def _draw_decor(self, canvas: Canvas):
        chest_x = max(3, self.width // 2 - 2)
        chest_y = self.floor_y - 1
        attr = curses.color_pair(COLOR_CORAL)
        canvas.addstr(chest_y, chest_x, "[__]", attr)
        canvas.addstr(chest_y - 1, chest_x + 1, "__", attr)
        canvas.addch(chest_y - 1, chest_x + 2, "o", curses.color_pair(COLOR_GOLD) | curses.A_BOLD)

        rock_y = self.floor_y - 1
        for rock_x in range(5, self.width - 5, 16):
            canvas.addstr(rock_y, rock_x, "_/\\_", curses.color_pair(COLOR_SILVER) | curses.A_DIM)

        star_x = max(4, self.width - 8)
        canvas.addstr(self.floor_y - 1, star_x, "\\|/", curses.color_pair(COLOR_CORAL))
        canvas.addch(self.floor_y - 2, star_x + 1, "*", curses.color_pair(COLOR_GOLD))

    def _draw_sand(self, canvas: Canvas):
        sand_attr = curses.color_pair(COLOR_SAND)
        ridge_attr = curses.color_pair(COLOR_SAND) | curses.A_DIM
        for x in range(1, self.width - 1):
            sand = "." if (x + int(self.total_time * 3.0)) % 3 else ","
            ridge = "_" if (x + int(self.total_time * 5.0)) % 9 else "~"
            canvas.addch(self.floor_y, x, sand, sand_attr)
            if self.floor_y - 1 > 0:
                canvas.addch(self.floor_y - 1, x, ridge if x % 5 == 0 else " ", ridge_attr)


def clamp_int(value: int, lower: int, upper: int) -> int:
    return max(lower, min(upper, value))


def init_colors():
    if not curses.has_colors():
        return
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(COLOR_WATER, curses.COLOR_BLUE, -1)
    curses.init_pair(COLOR_SAND, curses.COLOR_YELLOW, -1)
    curses.init_pair(COLOR_PLANT, curses.COLOR_GREEN, -1)
    curses.init_pair(COLOR_BUBBLE, curses.COLOR_CYAN, -1)
    curses.init_pair(COLOR_FOOD, curses.COLOR_WHITE, -1)
    curses.init_pair(COLOR_GOLD, curses.COLOR_YELLOW, -1)
    curses.init_pair(COLOR_NEON, curses.COLOR_CYAN, -1)
    curses.init_pair(COLOR_CORAL, curses.COLOR_MAGENTA, -1)
    curses.init_pair(COLOR_SILVER, curses.COLOR_WHITE, -1)
    curses.init_pair(COLOR_BARRACUDA, curses.COLOR_RED, -1)


def render_meter(ratio: float, width: int = 10) -> str:
    filled = int(clamp(ratio, 0.0, 1.0) * width)
    return "[" + ("#" * filled).ljust(width, "-") + "]"


def draw_frame(stdscr: curses.window, world: World):
    stdscr.erase()
    stdscr.box()
    canvas = Canvas(stdscr)
    world.draw(canvas)

    if world.show_hud:
        title = " Aquarium v2 "
        status_parts = [
            f"fish {len(world.fishes)}",
            f"food {len(world.foods)}",
            f"bubbles {len(world.bubbles)}",
            "paused" if world.paused else "swimming",
        ]
        if world.countdown_total is not None:
            ratio = world.countdown_remaining / world.countdown_total if world.countdown_total else 0.0
            status_parts.append(f"dial {render_meter(ratio)} {math.ceil(world.countdown_remaining):02d}s")
            if world.countdown_remaining <= 0.0:
                status_parts.append("depleting")
        status = "  ".join(status_parts)
        footer = "q quit  space pause  f food  b bubbles  B barracuda  +/- fish  c current  h hud/help"
        canvas.addstr(0, 2, title, curses.color_pair(COLOR_BUBBLE) | curses.A_BOLD)
        canvas.addstr(0, max(2, world.width - len(status) - 3), status, curses.color_pair(COLOR_BUBBLE) | curses.A_DIM)
        canvas.addstr(world.height - 1, 2, footer[: max(0, world.width - 4)], curses.color_pair(COLOR_BUBBLE) | curses.A_DIM)

    if world.show_help:
        help_lines = [
            "drop food and the hungrier fish will break formation for it",
            "currents add drift; bubble vents and scenery keep the tank busy",
            "press h to hide this panel",
        ]
        panel_width = min(world.width - 4, max(len(line) for line in help_lines) + 4)
        start_x = 3
        start_y = 2
        for i, line in enumerate(help_lines):
            text = f" {line[: panel_width - 2]} ".ljust(panel_width)
            canvas.addstr(start_y + i, start_x, text, curses.color_pair(COLOR_WATER))

    if world.width < 42 or world.height < 16:
        warning = "terminal is small; enlarge it for the full tank"
        canvas.addstr(world.height // 2, max(2, (world.width - len(warning)) // 2), warning, curses.color_pair(COLOR_FOOD) | curses.A_BOLD)

    stdscr.refresh()


def handle_input(stdscr: curses.window, world: World) -> bool:
    key = stdscr.getch()
    if key == -1:
        return True

    if key in (ord("q"), 27):
        return False
    if key == ord(" "):
        world.paused = not world.paused
    elif key == ord("f"):
        world.drop_food()
    elif key == ord("b"):
        world.bubble_burst()
    elif key in (ord("+"), ord("=")):
        world.add_fish()
    elif key in (ord("-"), ord("_")):
        world.remove_fish()
    elif key == ord("B"):
        world.summon_barracuda()
    elif key == ord("c"):
        world.currents = not world.currents
    elif key == ord("h"):
        if world.show_hud and world.show_help:
            world.show_help = False
        elif world.show_hud and not world.show_help:
            world.show_hud = False
        else:
            world.show_hud = True
            world.show_help = True
    elif key == curses.KEY_MOUSE:
        try:
            _, mx, my, _, _ = curses.getmouse()
            world.on_mouse_move(float(mx), float(my))
        except curses.error:
            pass
    return True


def run(stdscr: curses.window, args: argparse.Namespace):
    curses.curs_set(0)
    stdscr.nodelay(True)
    stdscr.timeout(0)
    curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
    init_colors()

    height, width = stdscr.getmaxyx()
    world = World(width, height, args.fish, countdown_seconds=args.countdown)
    if args.zen:
        world.show_hud = False
        world.show_help = False

    last = time.time()
    while True:
        now = time.time()
        dt = min(0.08, now - last)
        last = now

        height, width = stdscr.getmaxyx()
        if height != world.height or width != world.width:
            world.resize(width, height)

        if not handle_input(stdscr, world):
            break

        world.update(dt)
        draw_frame(stdscr, world)

        elapsed = time.time() - now
        sleep_time = max(0.0, (1.0 / args.fps) - elapsed)
        if sleep_time:
            time.sleep(sleep_time)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="A richer ASCII aquarium for the terminal.")
    parser.add_argument("--fish", type=int, default=12, help="Initial fish count.")
    parser.add_argument("--fps", type=int, default=24, help="Target frames per second.")
    parser.add_argument("--seed", type=int, default=None, help="Random seed for reproducible tanks.")
    parser.add_argument("--countdown", type=float, default=None, help="Seconds before the dial drains and the tank depletes to zero.")
    parser.add_argument("--zen", action="store_true", help="Start with HUD and help hidden.")
    return parser.parse_args()


def main():
    args = parse_args()
    if args.seed is not None:
        random.seed(args.seed)
    curses.wrapper(lambda stdscr: run(stdscr, args))


if __name__ == "__main__":
    main()
