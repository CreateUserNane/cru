<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;

class AuthController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        $request->merge([
            'username' => $request->input('username', $request->input('name')),
        ]);
        $data = $request->validate([
            'username' => ['required', 'string', 'min:2', 'max:40', 'unique:users,username'],
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'password' => ['required', 'string', 'min:6'],
        ]);

        $user = User::create([
            'name' => $data['username'], 'username' => $data['username'],
            'email' => $data['email'], 'password' => $data['password'],
        ]);

        return response()->json(['user' => $this->userData($user)], 201);
    }

    public function login(Request $request): JsonResponse
    {
        $data = $request->validate(['email' => ['required', 'email'], 'password' => ['required', 'string']]);
        $user = User::where('email', $data['email'])->first();
        if (! $user || ! Hash::check($data['password'], $user->password)) {
            return response()->json(['message' => 'Email or password is incorrect.'], 422);
        }

        return response()->json([
            'user' => $this->userData($user),
            'token' => $user->createToken('cru-mobile')->plainTextToken,
        ]);
    }

    public function user(Request $request): JsonResponse
    {
        return response()->json(['user' => $this->userData($request->user())]);
    }

    public function update(Request $request): JsonResponse
    {
        $user = $request->user();
        $request->merge([
            'username' => $request->input('username', $request->input('name')),
        ]);
        $data = $request->validate([
            'username' => ['required', 'string', 'min:2', 'max:40', Rule::unique('users', 'username')->ignore($user->id)],
            'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')->ignore($user->id)],
            'password' => ['nullable', 'string', 'min:6'],
        ]);

        $user->username = $data['username'];
        $user->name = $data['username'];
        $user->email = $data['email'];
        if (! empty($data['password'])) {
            $user->password = $data['password'];
        }
        $user->save();

        return response()->json(['user' => $this->userData($user)]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Logged out.']);
    }

    /** @return array{id: int, username: string, email: string} */
    private function userData(User $user): array
    {
        return ['id' => $user->id, 'username' => $user->username, 'email' => $user->email];
    }
}
